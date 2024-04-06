use aiken/hash.{Blake2b_224, Hash}
use aiken/transaction/credential.{VerificationKey}
use aiken/transaction/value.{AssetName, PolicyId}

pub type POSIXTime =
  Int

pub type AssetClass {
  policy_id: PolicyId,
  asset_name: AssetName,
}

pub type LoanOfferDatum {
  collateral_asset: AssetClass,
  collateral_amount: Int,
  interest_asset: AssetClass,
  interest_amount: Int,
  loan_asset: AssetClass,
  loan_amount: Int,
  loan_duration: POSIXTime,
  lender_address_hash: Hash<Blake2b_224, VerificationKey>,
}

pub type CollaeralDatum {
  loan_asset: AssetClass,
  loan_amount: Int,
  interest_asset: AssetClass,
  interest_amount: Int,
  collateral_asset: AssetClass,
  collateral_amount: Int,
  loan_duration: POSIXTime,
  lend_time: POSIXTime,
  liquidation_commision: Int,
  lender_address_hash: Hash<Blake2b_224, VerificationKey>,
}

pub type InterestDatum {
  lender_address_hash: Hash<Blake2b_224, VerificationKey>,
}
