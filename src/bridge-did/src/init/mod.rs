pub mod brc20;
mod bridge_data;
pub mod btc;
pub mod erc20;
mod rune;

use std::time::Duration;

pub use bridge_data::*;
pub use btc::BtcBridgeConfig;
pub use rune::*;

pub const DEFAULT_DEPOSIT_FEE: u64 = 100_000;
pub const DEFAULT_MEMPOOL_TIMEOUT: Duration = Duration::from_secs(24 * 60 * 60);

/// Minimum number of indexers required to start the bridge.
pub const MIN_INDEXERS: usize = 2;
pub const DEFAULT_INDEXER_CONSENSUS_THRESHOLD: u8 = 2;
