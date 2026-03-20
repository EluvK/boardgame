mod constants;
mod engine;
mod model;

#[cfg(test)]
mod tests;

pub use model::{
    AcquireState, CompanyState, FinalStanding, FoundingContext, MergeContext, MergeSettlement,
};

pub(crate) use constants::{BOARD_MAX_COL, BOARD_MAX_ROW, COMPANY_IDS};
pub(crate) use model::PlacementKind;

#[derive(Clone)]
pub struct AcquireGame;

impl AcquireGame {
    pub fn new() -> Self {
        Self {}
    }
}
