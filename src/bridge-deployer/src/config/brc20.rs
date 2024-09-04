use std::time::Duration;

use clap::{Parser, ValueEnum};
use ic_exports::ic_cdk::api::management_canister::bitcoin;
use serde::{Deserialize, Serialize};

#[derive(Parser, Debug, Serialize, Deserialize, Clone)]
pub struct Brc20BridgeConfig {
    /// The network to use for the Bitcoin blockchain
    #[arg(long)]
    pub bitcoin_network: BitcoinNetwork,
    /// The minimum number of confirmations required for a Bitcoin transaction
    /// to be considered final
    #[arg(long)]
    pub min_confirmations: u32,
    /// The URLs of the indexers to use for the Bitcoin blockchain
    ///
    /// Note: The number of URLs must match the number of indexers specified above
    #[arg(long, value_delimiter = ',')]
    pub indexer_urls: Vec<String>,
    /// The fee to charge for deposits
    #[arg(long)]
    pub deposit_fee: u64,
    /// The timeout for the mempool to confirm a transaction
    #[arg(long)]
    pub mempool_timeout: u64,
    /// The threshold for the indexer consensus
    #[arg(long)]
    pub indexer_consensus_threshold: u8,
}

#[derive(ValueEnum, Serialize, Deserialize, Debug, Clone)]
pub enum BitcoinNetwork {
    Mainnet,
    Testnet,
    Regtest,
}

impl From<BitcoinNetwork> for bitcoin::BitcoinNetwork {
    fn from(value: BitcoinNetwork) -> Self {
        match value {
            BitcoinNetwork::Mainnet => Self::Mainnet,
            BitcoinNetwork::Testnet => Self::Testnet,
            BitcoinNetwork::Regtest => Self::Regtest,
        }
    }
}

impl From<Brc20BridgeConfig> for brc20_bridge::state::Brc20BridgeConfig {
    fn from(value: Brc20BridgeConfig) -> Self {
        Self {
            network: value.bitcoin_network.into(),
            min_confirmations: value.min_confirmations,
            indexer_urls: value.indexer_urls.into_iter().collect(),
            deposit_fee: value.deposit_fee,
            mempool_timeout: Duration::from_secs(value.mempool_timeout),
            indexer_consensus_threshold: value.indexer_consensus_threshold,
        }
    }
}
