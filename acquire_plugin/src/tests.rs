#[cfg(test)]
mod tests {
    use crate::*;
    use boardgames_server::game::{self, Action, ActionCtx, ActionResult, Game, GameState};
    use serde_json::{Value, json};
    use std::collections::HashSet;

    fn make_action(user: &str, payload: Value) -> Action {
        Action {
            id: "a1".to_string(),
            user_id: user.to_string(),
            payload,
            seq: None,
            meta: None,
        }
    }

    fn test_ctx() -> ActionCtx {
        ActionCtx {
            room_id: "r1".to_string(),
            session_id: None,
            now_ts: 0,
            ext: None,
        }
    }

    fn downcast_state(state: &dyn GameState) -> &AcquireState {
        let any = state as &dyn std::any::Any;
        any.downcast_ref::<AcquireState>()
            .expect("state should be AcquireState")
    }

    fn downcast_state_mut(state: &mut dyn GameState) -> &mut AcquireState {
        let any = state as &mut dyn std::any::Any;
        any.downcast_mut::<AcquireState>()
            .expect("state should be AcquireState")
    }

    fn grant_tile(state: &mut Box<dyn GameState>, user: &str, pos: &str) {
        let s = downcast_state_mut(state.as_mut());
        s.player_tiles
            .entry(user.to_string())
            .or_default()
            .insert(pos.to_string());
        s.tile_bag.retain(|t| t != pos);
    }

    async fn place_and_buy_zero(
        game: &AcquireGame,
        ctx: &ActionCtx,
        state: &mut Box<dyn GameState>,
        user: &str,
        pos: &str,
    ) {
        grant_tile(state, user, pos);
        let place = game
            .handle_action(
                ctx,
                state.as_mut(),
                make_action(user, json!({"type":"place", "pos":pos})),
            )
            .await;
        assert!(matches!(place, ActionResult::Ok { .. }));

        if downcast_state(state.as_ref()).phase == "choose_company" {
            let company = downcast_state(state.as_ref())
                .first_inactive_company()
                .expect("at least one company available to found");
            let choose = game
                .handle_action(
                    ctx,
                    state.as_mut(),
                    make_action(user, json!({"type":"choose_company","company":company})),
                )
                .await;
            assert!(matches!(choose, ActionResult::Ok { .. }));
        }

        let buy = game
            .handle_action(
                ctx,
                state.as_mut(),
                make_action(user, json!({"type":"buy", "purchases": {}})),
            )
            .await;
        assert!(matches!(buy, ActionResult::Ok { .. }));
    }

    async fn setup_merge_stock_decision_state(
        game: &AcquireGame,
        ctx: &ActionCtx,
    ) -> Box<dyn GameState> {
        let mut state = game.create_initial_state(None).await;

        let _ = game.on_join(ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(ctx, state.as_mut(), "u2".to_string()).await;

        place_and_buy_zero(game, ctx, &mut state, "u1", "1A").await;
        place_and_buy_zero(game, ctx, &mut state, "u2", "2A").await; // found Worldwide
        place_and_buy_zero(game, ctx, &mut state, "u1", "1C").await;

        // Found Sackson and buy one extra share so u2 has 2 shares total in loser company.
        grant_tile(&mut state, "u2", "2C");
        let found_sackson = game
            .handle_action(
                ctx,
                state.as_mut(),
                make_action("u2", json!({"type":"place","pos":"2C"})),
            )
            .await;
        assert!(matches!(found_sackson, ActionResult::Ok { .. }));
        let choose_sackson = game
            .handle_action(
                ctx,
                state.as_mut(),
                make_action("u2", json!({"type":"choose_company","company":"Sackson"})),
            )
            .await;
        assert!(matches!(choose_sackson, ActionResult::Ok { .. }));
        let buy_sackson = game
            .handle_action(
                ctx,
                state.as_mut(),
                make_action("u2", json!({"type":"buy","purchases":{"Sackson":1}})),
            )
            .await;
        assert!(matches!(buy_sackson, ActionResult::Ok { .. }));

        // Trigger tie merge and resolve survivor as Worldwide.
        grant_tile(&mut state, "u1", "1B");
        let place_merge = game
            .handle_action(
                ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"place", "pos":"1B"})),
            )
            .await;
        assert!(matches!(place_merge, ActionResult::Ok { .. }));

        let resolve = game
            .handle_action(
                ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"resolve_merge","survivor":"Worldwide"})),
            )
            .await;
        assert!(matches!(resolve, ActionResult::Ok { .. }));

        let s = downcast_state(state.as_ref());
        assert_eq!(s.phase, "merge_stock_decision");

        state
    }

    #[tokio::test]
    async fn requires_two_players_before_actions() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let res = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"place", "pos":"1A"})),
            )
            .await;

        match res {
            ActionResult::Err(game::GameError::Invalid(e)) => {
                assert_eq!(e, "not_enough_players_min_2")
            }
            _ => panic!("expected not_enough_players_min_2"),
        }
    }

    #[tokio::test]
    async fn enforces_turn_order_and_phase_transition() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u2".to_string()).await;

        // wrong player cannot place first
        let wrong = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u2", json!({"type":"place", "pos":"1A"})),
            )
            .await;
        match wrong {
            ActionResult::Err(game::GameError::Invalid(e)) => assert_eq!(e, "not_your_turn"),
            _ => panic!("expected not_your_turn"),
        }

        // current player places tile, phase moves to buy
        let place = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"place", "pos":"1A"})),
            )
            .await;
        assert!(matches!(place, ActionResult::Ok { .. }));

        let s = downcast_state(state.as_ref());
        assert_eq!(s.phase, "buy");
        assert_eq!(s.current_player(), Some("u1"));
    }

    #[tokio::test]
    async fn buy_limits_and_turn_advance_work() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u2".to_string()).await;

        let _ = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"place", "pos":"1A"})),
            )
            .await;

        // invalid buy over limit
        let invalid_buy = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"buy", "purchases": {"Worldwide": 4}})),
            )
            .await;
        match invalid_buy {
            ActionResult::Err(game::GameError::Invalid(e)) => assert_eq!(e, "invalid shares"),
            _ => panic!("expected invalid shares"),
        }

        // malformed payload without purchases map should fail.
        let missing_purchases = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"buy", "shares": 1})),
            )
            .await;
        match missing_purchases {
            ActionResult::Err(game::GameError::Invalid(e)) => {
                assert_eq!(e, "invalid_buy_purchases")
            }
            _ => panic!("expected invalid_buy_purchases"),
        }

        // buy zero still advances to next player's place phase.
        let ok_buy = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"buy", "purchases": {}})),
            )
            .await;
        assert!(matches!(ok_buy, ActionResult::Ok { .. }));

        let s = downcast_state(state.as_ref());
        assert_eq!(s.phase, "place");
        assert_eq!(s.current_player(), Some("u2"));
        assert_eq!(s.players.get("u1").copied().unwrap_or(0), 6000);
    }

    #[tokio::test]
    async fn merge_tie_requires_resolve_then_allows_buy() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u2".to_string()).await;

        place_and_buy_zero(&game, &ctx, &mut state, "u1", "1A").await;
        place_and_buy_zero(&game, &ctx, &mut state, "u2", "2A").await; // found company 1
        place_and_buy_zero(&game, &ctx, &mut state, "u1", "1C").await;
        place_and_buy_zero(&game, &ctx, &mut state, "u2", "2C").await; // found company 2

        grant_tile(&mut state, "u1", "1B");
        let place_merge = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"place", "pos":"1B"})),
            )
            .await;
        assert!(matches!(place_merge, ActionResult::Ok { .. }));

        let s = downcast_state(state.as_ref());
        assert_eq!(s.phase, "resolve_merge");
        let merge_ctx = s
            .merge_context
            .as_ref()
            .expect("merge context should be set");
        assert_eq!(merge_ctx.allowed_survivors.len(), 2);

        let resolve = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"resolve_merge","survivor":"Worldwide"})),
            )
            .await;
        assert!(matches!(resolve, ActionResult::Ok { .. }));

        let s = downcast_state(state.as_ref());
        assert_eq!(s.phase, "merge_stock_decision");
        assert!(s.merge_context.is_none());
        assert_eq!(s.companies.len(), 2);

        let stock_decision = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action(
                    "u2",
                    json!({"type":"merge_stock_decision","company":"Sackson","mode":"hold"}),
                ),
            )
            .await;
        assert!(matches!(stock_decision, ActionResult::Ok { .. }));

        let s = downcast_state(state.as_ref());
        assert_eq!(s.phase, "buy");
        assert_eq!(s.companies.len(), 1);

        let buy_after_resolve = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"buy", "purchases": {}})),
            )
            .await;
        assert!(matches!(buy_after_resolve, ActionResult::Ok { .. }));
    }

    #[tokio::test]
    async fn buy_uses_company_tier_and_size_price() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u2".to_string()).await;

        // Build first company (Worldwide) with size 2 at 1A + 2A.
        place_and_buy_zero(&game, &ctx, &mut state, "u1", "1A").await;
        let found = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u2", json!({"type":"place","pos":"2A"})),
            )
            .await;
        assert!(matches!(found, ActionResult::Ok { .. }));

        let choose = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u2", json!({"type":"choose_company","company":"Worldwide"})),
            )
            .await;
        assert!(matches!(choose, ActionResult::Ok { .. }));

        // Worldwide size=2 => price 200; buy 1 share should deduct 200 from 6000.
        let buy = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u2", json!({"type":"buy","purchases":{"Worldwide":1}})),
            )
            .await;
        assert!(matches!(buy, ActionResult::Ok { .. }));

        let s = downcast_state(state.as_ref());
        assert_eq!(s.players.get("u2").copied().unwrap_or(0), 5800);
        let holding = s
            .shares
            .get("u2")
            .and_then(|m| m.get("Worldwide"))
            .copied()
            .unwrap_or(0);
        // u2 gets 1 founder share + 1 bought share.
        assert_eq!(holding, 2);
    }

    #[tokio::test]
    async fn merge_stock_decision_sell_updates_cash_and_holding() {
        let game = AcquireGame::new();
        let ctx = test_ctx();
        let mut state = setup_merge_stock_decision_state(&game, &ctx).await;

        let before_pool = downcast_state(state.as_ref())
            .stock_pool
            .get("Sackson")
            .copied()
            .unwrap_or(0);
        let before_cash = downcast_state(state.as_ref())
            .players
            .get("u2")
            .copied()
            .unwrap_or(0);

        let sell = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action(
                    "u2",
                    json!({"type":"merge_stock_decision","company":"Sackson","mode":"sell","shares":2}),
                ),
            )
            .await;
        assert!(matches!(sell, ActionResult::Ok { .. }));

        let s = downcast_state(state.as_ref());
        let after_cash = s.players.get("u2").copied().unwrap_or(0);
        let loser_holding = s
            .shares
            .get("u2")
            .and_then(|m| m.get("Sackson"))
            .copied()
            .unwrap_or(0);
        let after_pool = s.stock_pool.get("Sackson").copied().unwrap_or(0);
        assert_eq!(after_cash - before_cash, 400);
        assert_eq!(loser_holding, 0);
        assert_eq!(after_pool - before_pool, 2);
        assert_eq!(s.phase, "buy");
    }

    #[tokio::test]
    async fn merge_stock_decision_trade_converts_two_to_one() {
        let game = AcquireGame::new();
        let ctx = test_ctx();
        let mut state = setup_merge_stock_decision_state(&game, &ctx).await;

        let before = downcast_state(state.as_ref());
        let before_cash = before.players.get("u2").copied().unwrap_or(0);
        let before_survivor_holding = before
            .shares
            .get("u2")
            .and_then(|m| m.get("Worldwide"))
            .copied()
            .unwrap_or(0);
        let before_pool = before.stock_pool.get("Worldwide").copied().unwrap_or(0);
        let before_loser_pool = before.stock_pool.get("Sackson").copied().unwrap_or(0);

        let trade = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action(
                    "u2",
                    json!({"type":"merge_stock_decision","company":"Sackson","mode":"trade","shares":2}),
                ),
            )
            .await;
        assert!(matches!(trade, ActionResult::Ok { .. }));

        let after = downcast_state(state.as_ref());
        let after_cash = after.players.get("u2").copied().unwrap_or(0);
        let after_survivor_holding = after
            .shares
            .get("u2")
            .and_then(|m| m.get("Worldwide"))
            .copied()
            .unwrap_or(0);
        let loser_holding = after
            .shares
            .get("u2")
            .and_then(|m| m.get("Sackson"))
            .copied()
            .unwrap_or(0);
        let after_pool = after.stock_pool.get("Worldwide").copied().unwrap_or(0);
        let after_loser_pool = after.stock_pool.get("Sackson").copied().unwrap_or(0);

        assert_eq!(after_cash, before_cash);
        assert_eq!(after_survivor_holding - before_survivor_holding, 1);
        assert_eq!(before_pool - after_pool, 1);
        assert_eq!(after_loser_pool - before_loser_pool, 2);
        assert_eq!(loser_holding, 0);
        assert_eq!(after.phase, "buy");
    }

    #[tokio::test]
    async fn cannot_merge_multiple_safe_companies() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u2".to_string()).await;

        {
            let s = downcast_state_mut(state.as_mut());
            s.tiles.insert("2A".to_string());
            s.tiles.insert("2C".to_string());
            s.tile_company.insert("2A".to_string(), "Worldwide".to_string());
            s.tile_company.insert("2C".to_string(), "Sackson".to_string());
            s.companies.insert(
                "Worldwide".to_string(),
                CompanyState {
                    id: "Worldwide".to_string(),
                    tiles: HashSet::from(["2A".to_string()]),
                    safe: true,
                },
            );
            s.companies.insert(
                "Sackson".to_string(),
                CompanyState {
                    id: "Sackson".to_string(),
                    tiles: HashSet::from(["2C".to_string()]),
                    safe: true,
                },
            );
        }

        grant_tile(&mut state, "u1", "2B");
        let act = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"place","pos":"2B"})),
            )
            .await;
        match act {
            ActionResult::Err(game::GameError::Invalid(e)) => {
                assert_eq!(e, "cannot_merge_multiple_safe_companies")
            }
            _ => panic!("expected cannot_merge_multiple_safe_companies"),
        }
    }

    #[tokio::test]
    async fn choose_company_requires_valid_and_inactive_company() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u2".to_string()).await;

        place_and_buy_zero(&game, &ctx, &mut state, "u1", "1A").await;

        grant_tile(&mut state, "u2", "2A");
        let place_found = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u2", json!({"type":"place","pos":"2A"})),
            )
            .await;
        assert!(matches!(place_found, ActionResult::Ok { .. }));
        assert_eq!(downcast_state(state.as_ref()).phase, "choose_company");

        let bad_choose = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u2", json!({"type":"choose_company","company":"NotExists"})),
            )
            .await;
        match bad_choose {
            ActionResult::Err(game::GameError::Invalid(e)) => assert_eq!(e, "unknown_company"),
            _ => panic!("expected unknown_company"),
        }

        let ok_choose = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u2", json!({"type":"choose_company","company":"Worldwide"})),
            )
            .await;
        assert!(matches!(ok_choose, ActionResult::Ok { .. }));
        assert_eq!(downcast_state(state.as_ref()).phase, "buy");

        let buy_zero = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u2", json!({"type":"buy","purchases":{}})),
            )
            .await;
        assert!(matches!(buy_zero, ActionResult::Ok { .. }));

        // u1 turn: create another founding opportunity
        grant_tile(&mut state, "u1", "1C");
        let p1 = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"place","pos":"1C"})),
            )
            .await;
        assert!(matches!(p1, ActionResult::Ok { .. }));
        let b1 = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"buy","purchases":{}})),
            )
            .await;
        assert!(matches!(b1, ActionResult::Ok { .. }));

        grant_tile(&mut state, "u2", "2C");
        let p2 = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u2", json!({"type":"place","pos":"2C"})),
            )
            .await;
        assert!(matches!(p2, ActionResult::Ok { .. }));
        assert_eq!(downcast_state(state.as_ref()).phase, "choose_company");

        // Worldwide already active, choosing again should fail.
        let dup_choose = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u2", json!({"type":"choose_company","company":"Worldwide"})),
            )
            .await;
        match dup_choose {
            ActionResult::Err(game::GameError::Invalid(e)) => {
                assert_eq!(e, "company_already_active")
            }
            _ => panic!("expected company_already_active"),
        }
    }

    #[tokio::test]
    async fn declare_end_rejected_when_conditions_not_met() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u2".to_string()).await;

        let res = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"declare_end"})),
            )
            .await;

        match res {
            ActionResult::Err(game::GameError::Invalid(e)) => {
                assert_eq!(e, "end_conditions_not_met")
            }
            _ => panic!("expected end_conditions_not_met"),
        }
    }

    #[tokio::test]
    async fn declare_end_scores_and_sets_winner() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u2".to_string()).await;

        {
            let s = downcast_state_mut(state.as_mut());
            let mut tiles = HashSet::new();
            for i in 0..41 {
                tiles.insert(format!("{}A", i + 1));
            }
            s.companies.insert(
                "Worldwide".to_string(),
                CompanyState {
                    id: "Worldwide".to_string(),
                    tiles,
                    safe: true,
                },
            );
            s.set_share_count("u1", "Worldwide", 3);
            s.set_share_count("u2", "Worldwide", 1);
        }

        let res = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"declare_end"})),
            )
            .await;
        assert!(matches!(res, ActionResult::Ok { .. }));

        let s = downcast_state(state.as_ref());
        assert!(s.game_over);
        assert_eq!(s.phase, "game_over");
        assert_eq!(s.final_standings.first().map(|x| x.user_id.as_str()), Some("u1"));

        // price at size 41 is 1000 for Worldwide.
        // u1: 6000 + bonus 10000 + liquidation 3000 = 19000
        // u2: 6000 + bonus 5000 + liquidation 1000 = 12000
        assert_eq!(s.players.get("u1").copied().unwrap_or(0), 19000);
        assert_eq!(s.players.get("u2").copied().unwrap_or(0), 12000);
    }

    #[tokio::test]
    async fn expand_absorbs_adjacent_independent_component() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u2".to_string()).await;

        {
            let s = downcast_state_mut(state.as_mut());
            s.tiles.insert("5E".to_string());
            s.tile_company
                .insert("5E".to_string(), "Worldwide".to_string());
            s.companies.insert(
                "Worldwide".to_string(),
                CompanyState {
                    id: "Worldwide".to_string(),
                    tiles: HashSet::from(["5E".to_string()]),
                    safe: false,
                },
            );
            s.tiles.insert("6E".to_string());
            s.tiles.insert("6F".to_string());
            s.independent_tiles.insert("6E".to_string());
            s.independent_tiles.insert("6F".to_string());
        }

        grant_tile(&mut state, "u1", "5F");
        let place = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"place","pos":"5F"})),
            )
            .await;
        assert!(matches!(place, ActionResult::Ok { .. }));

        let s = downcast_state(state.as_ref());
        let company = s
            .companies
            .get("Worldwide")
            .expect("Worldwide should stay active");
        assert!(company.tiles.contains("5E"));
        assert!(company.tiles.contains("5F"));
        assert!(company.tiles.contains("6E"));
        assert!(company.tiles.contains("6F"));
        assert!(!s.independent_tiles.contains("6E"));
        assert!(!s.independent_tiles.contains("6F"));
        assert_eq!(s.tile_company.get("6E").map(String::as_str), Some("Worldwide"));
        assert_eq!(s.tile_company.get("6F").map(String::as_str), Some("Worldwide"));
    }

    #[tokio::test]
    async fn declare_end_allowed_when_all_safe_and_no_founding_opportunity() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u2".to_string()).await;

        {
            let s = downcast_state_mut(state.as_mut());
            let mut world_tiles = HashSet::new();
            for col in 1..=11 {
                let pos = format!("{}A", col);
                s.tiles.insert(pos.clone());
                s.tile_company.insert(pos.clone(), "Worldwide".to_string());
                world_tiles.insert(pos);
            }
            s.companies.insert(
                "Worldwide".to_string(),
                CompanyState {
                    id: "Worldwide".to_string(),
                    tiles: world_tiles,
                    safe: true,
                },
            );

            let mut sackson_tiles = HashSet::new();
            for col in 1..=11 {
                let pos = format!("{}C", col);
                s.tiles.insert(pos.clone());
                s.tile_company.insert(pos.clone(), "Sackson".to_string());
                sackson_tiles.insert(pos);
            }
            s.companies.insert(
                "Sackson".to_string(),
                CompanyState {
                    id: "Sackson".to_string(),
                    tiles: sackson_tiles,
                    safe: true,
                },
            );
        }

        let res = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"declare_end"})),
            )
            .await;
        assert!(matches!(res, ActionResult::Ok { .. }));
        assert!(downcast_state(state.as_ref()).game_over);
    }

    #[tokio::test]
    async fn declare_end_rejected_when_founding_opportunity_exists() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u2".to_string()).await;

        {
            let s = downcast_state_mut(state.as_mut());
            let mut world_tiles = HashSet::new();
            for col in 1..=11 {
                let pos = format!("{}A", col);
                s.tiles.insert(pos.clone());
                s.tile_company.insert(pos.clone(), "Worldwide".to_string());
                world_tiles.insert(pos);
            }
            s.companies.insert(
                "Worldwide".to_string(),
                CompanyState {
                    id: "Worldwide".to_string(),
                    tiles: world_tiles,
                    safe: true,
                },
            );

            // 2B and 4B are independent neighbors of empty 3B, so 3B can found a new company.
            for pos in ["2B", "4B"] {
                s.tiles.insert(pos.to_string());
                s.independent_tiles.insert(pos.to_string());
            }
        }

        let res = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"declare_end"})),
            )
            .await;

        match res {
            ActionResult::Err(game::GameError::Invalid(e)) => {
                assert_eq!(e, "end_conditions_not_met")
            }
            _ => panic!("expected end_conditions_not_met"),
        }
    }

    #[tokio::test]
    async fn declare_end_ignores_inactive_company_holdings_in_liquidation() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u2".to_string()).await;

        {
            let s = downcast_state_mut(state.as_mut());
            let mut tiles = HashSet::new();
            for i in 0..41 {
                tiles.insert(format!("{}A", i + 1));
            }
            s.companies.insert(
                "Worldwide".to_string(),
                CompanyState {
                    id: "Worldwide".to_string(),
                    tiles,
                    safe: true,
                },
            );

            s.set_share_count("u1", "Worldwide", 1);
            s.set_share_count("u1", "Imperial", 3);
            s.set_share_count("u2", "Worldwide", 1);
        }

        let res = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"declare_end"})),
            )
            .await;
        assert!(matches!(res, ActionResult::Ok { .. }));

        let s = downcast_state(state.as_ref());
        // u1 and u2 tie for first in Worldwide, so they split (major+minor)=15000 => 7500 each.
        // u1 gets: initial 6000 + tie bonus 7500 + Worldwide liquidation 1000 = 14500.
        // Imperial is inactive and must not contribute to liquidation.
        assert_eq!(s.players.get("u1").copied().unwrap_or(0), 14500);
    }

    #[tokio::test]
    async fn on_join_deals_initial_six_tiles_per_player() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u2".to_string()).await;

        let s = downcast_state(state.as_ref());
        assert_eq!(s.player_tiles.get("u1").map(HashSet::len).unwrap_or(0), 6);
        assert_eq!(s.player_tiles.get("u2").map(HashSet::len).unwrap_or(0), 6);
        assert_eq!(s.tile_bag.len(), (BOARD_MAX_COL * BOARD_MAX_ROW - 12) as usize);
    }

    #[tokio::test]
    async fn draw_tile_requires_non_full_hand_and_draws_when_available() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u2".to_string()).await;

        let full_hand_draw = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"draw_tile"})),
            )
            .await;
        match full_hand_draw {
            ActionResult::Err(game::GameError::Invalid(e)) => assert_eq!(e, "hand_already_full"),
            _ => panic!("expected hand_already_full"),
        }

        {
            let s = downcast_state_mut(state.as_mut());
            let removed = s
                .player_tiles
                .get_mut("u1")
                .and_then(|h| h.iter().next().cloned())
                .expect("u1 should have a tile");
            s.player_tiles
                .get_mut("u1")
                .expect("u1 hand exists")
                .remove(&removed);
        }

        let draw_ok = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"draw_tile"})),
            )
            .await;
        assert!(matches!(draw_ok, ActionResult::Ok { .. }));

        let s = downcast_state(state.as_ref());
        assert_eq!(s.player_tiles.get("u1").map(HashSet::len).unwrap_or(0), 6);
    }

    #[tokio::test]
    async fn place_rejected_when_tile_not_in_hand() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u2".to_string()).await;

        let res = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"place", "pos":"12I"})),
            )
            .await;

        match res {
            ActionResult::Err(game::GameError::Invalid(e)) => assert_eq!(e, "tile_not_in_hand"),
            _ => panic!("expected tile_not_in_hand"),
        }
    }

    #[tokio::test]
    async fn merge_stock_decision_allows_partial_then_finalize() {
        let game = AcquireGame::new();
        let ctx = test_ctx();
        let mut state = setup_merge_stock_decision_state(&game, &ctx).await;

        let sell_one = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action(
                    "u2",
                    json!({"type":"merge_stock_decision","company":"Sackson","mode":"sell","shares":1}),
                ),
            )
            .await;
        assert!(matches!(sell_one, ActionResult::Ok { .. }));

        let s_mid = downcast_state(state.as_ref());
        assert_eq!(s_mid.phase, "merge_stock_decision");
        let remaining = s_mid
            .shares
            .get("u2")
            .and_then(|m| m.get("Sackson"))
            .copied()
            .unwrap_or(0);
        assert_eq!(remaining, 1);

        let hold_rest = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action(
                    "u2",
                    json!({"type":"merge_stock_decision","company":"Sackson","mode":"hold"}),
                ),
            )
            .await;
        assert!(matches!(hold_rest, ActionResult::Ok { .. }));

        let s = downcast_state(state.as_ref());
        assert_eq!(s.phase, "buy");
        assert!(s.companies.contains_key("Worldwide"));
        assert!(!s.companies.contains_key("Sackson"));
    }

    #[tokio::test]
    async fn merge_stock_decision_is_sequential_from_trigger_player() {
        let game = AcquireGame::new();
        let ctx = test_ctx();
        let mut state = setup_merge_stock_decision_state(&game, &ctx).await;

        {
            let s = downcast_state_mut(state.as_mut());
            s.set_share_count("u1", "Sackson", 1);
            if let Some(settlement) = s.merge_settlement.as_mut() {
                settlement
                    .pending
                    .entry("u1".to_string())
                    .or_insert_with(HashSet::new)
                    .insert("Sackson".to_string());
            }
        }

        let before = downcast_state(state.as_ref());
        assert_eq!(before.current_player(), Some("u1"));

        // u2 cannot decide before u1 when both have pending loser shares.
        let u2_early = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action(
                    "u2",
                    json!({"type":"merge_stock_decision","company":"Sackson","mode":"hold"}),
                ),
            )
            .await;
        match u2_early {
            ActionResult::Err(game::GameError::Invalid(e)) => assert_eq!(e, "not_your_turn"),
            _ => panic!("expected not_your_turn"),
        }

        let u1_decide = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action(
                    "u1",
                    json!({"type":"merge_stock_decision","company":"Sackson","mode":"hold"}),
                ),
            )
            .await;
        assert!(matches!(u1_decide, ActionResult::Ok { .. }));

        let mid = downcast_state(state.as_ref());
        assert_eq!(mid.phase, "merge_stock_decision");

        // u1 has finished all pending loser decisions, cannot act again before u2.
        let u1_again = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action(
                    "u1",
                    json!({"type":"merge_stock_decision","company":"Sackson","mode":"hold"}),
                ),
            )
            .await;
        match u1_again {
            ActionResult::Err(game::GameError::Invalid(e)) => assert_eq!(e, "not_your_turn"),
            _ => panic!("expected not_your_turn"),
        }

        let u2_decide = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action(
                    "u2",
                    json!({"type":"merge_stock_decision","company":"Sackson","mode":"hold"}),
                ),
            )
            .await;
        assert!(matches!(u2_decide, ActionResult::Ok { .. }));

        let after = downcast_state(state.as_ref());
        assert_eq!(after.phase, "buy");
    }

    #[tokio::test]
    async fn classify_placement_covers_four_outcomes() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let s = downcast_state_mut(state.as_mut());

        // isolated
        assert!(matches!(s.classify_placement("8H"), PlacementKind::Isolated));

        // founding candidate: adjacent to independent tiles and no adjacent company.
        for pos in ["5D", "5F"] {
            s.tiles.insert(pos.to_string());
            s.independent_tiles.insert(pos.to_string());
        }
        assert!(matches!(
            s.classify_placement("5E"),
            PlacementKind::FoundCandidate
        ));

        // expand: adjacent to exactly one company.
        s.tiles.insert("9D".to_string());
        s.tile_company
            .insert("9D".to_string(), "Worldwide".to_string());
        assert!(matches!(
            s.classify_placement("9E"),
            PlacementKind::Expand(ref cid) if cid == "Worldwide"
        ));

        // merge: adjacent to two different companies.
        for (pos, cid) in [("2D", "Worldwide"), ("2F", "Sackson")] {
            s.tiles.insert(pos.to_string());
            s.tile_company.insert(pos.to_string(), cid.to_string());
        }
        assert!(matches!(
            s.classify_placement("2E"),
            PlacementKind::Merge(ref cids) if cids.len() == 2 && cids.iter().any(|c| c == "Worldwide") && cids.iter().any(|c| c == "Sackson")
        ));
    }

    #[tokio::test]
    async fn snapshot_restore_keeps_turn_and_phase_consistent() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u2".to_string()).await;

        place_and_buy_zero(&game, &ctx, &mut state, "u1", "1A").await;

        let before = downcast_state(state.as_ref());
        let before_current = before.current_player().map(str::to_string);
        let before_phase = before.phase.clone();
        let before_turn = before.turn_no;
        let before_tiles = before.tiles.clone();

        let snapshot = state
            .snapshot()
            .expect("snapshot should serialize acquire state");

        let mut restored = game.create_initial_state(None).await;
        restored
            .restore(&snapshot)
            .expect("restore should load acquire state snapshot");

        let after = downcast_state(restored.as_ref());
        assert_eq!(after.current_player(), before_current.as_deref());
        assert_eq!(after.phase, before_phase);
        assert_eq!(after.turn_no, before_turn);
        assert_eq!(after.tiles, before_tiles);
    }

    #[tokio::test]
    async fn declare_end_bonus_distribution_handles_second_place_tie() {
        let game = AcquireGame::new();
        let mut state = game.create_initial_state(None).await;
        let ctx = test_ctx();

        let _ = game.on_join(&ctx, state.as_mut(), "u1".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u2".to_string()).await;
        let _ = game.on_join(&ctx, state.as_mut(), "u3".to_string()).await;

        {
            let s = downcast_state_mut(state.as_mut());
            let mut tiles = HashSet::new();
            for i in 0..41 {
                tiles.insert(format!("{}A", i + 1));
            }
            s.companies.insert(
                "Worldwide".to_string(),
                CompanyState {
                    id: "Worldwide".to_string(),
                    tiles,
                    safe: true,
                },
            );

            s.set_share_count("u1", "Worldwide", 4);
            s.set_share_count("u2", "Worldwide", 2);
            s.set_share_count("u3", "Worldwide", 2);
        }

        let res = game
            .handle_action(
                &ctx,
                state.as_mut(),
                make_action("u1", json!({"type":"declare_end"})),
            )
            .await;
        assert!(matches!(res, ActionResult::Ok { .. }));

        let s = downcast_state(state.as_ref());
        // Worldwide size 41 => price 1000.
        // u1: 6000 + 10000 + 4000 = 20000
        // u2: 6000 + 2500 + 2000 = 10500
        // u3: 6000 + 2500 + 2000 = 10500
        assert_eq!(s.players.get("u1").copied().unwrap_or(0), 20000);
        assert_eq!(s.players.get("u2").copied().unwrap_or(0), 10500);
        assert_eq!(s.players.get("u3").copied().unwrap_or(0), 10500);
    }
}
