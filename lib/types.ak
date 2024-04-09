use aiken/hash.{Blake2b_224, Hash}
use aiken/transaction.{TransactionId}
use aiken/transaction/credential.{Script, VerificationKey}
use aiken/transaction/value.{AssetName, PolicyId, Value}

pub type POSIXTime =
  Int

pub type AssetClass {
  policy_id: PolicyId,
  asset_name: AssetName,
}

pub type AddressHash =
  Hash<Blake2b_224, VerificationKey>

pub type LoanOfferDatum {
  loan_asset: AssetClass,
  loan_amount: Int,
  collateral_asset: AssetClass,
  collateral_amount: Int,
  collateral_percent: Int,
  interest_asset: AssetClass,
  interest_amount: Int,
  interest_percent: Int,
  loan_duration: POSIXTime,
  lender_address_hash: AddressHash,
}

pub type CollateralDatum {
  loan_asset: AssetClass,
  loan_amount: Int,
  interest_asset: AssetClass,
  interest_amount: Int,
  collateral_asset: AssetClass,
  loan_duration: POSIXTime,
  lend_time: POSIXTime,
  total_loan_amount: Int,
  lender_address_hash: AddressHash,
  borrower_address_hash: AddressHash,
  tx_id: TransactionId,
}

pub type InterestDatum {
  lender_address_hash: AddressHash,
}

pub type AddressAndValue {
  address_hash: AddressHash,
  value: Value,
}

pub type Info {
  collateral_amount: Int,
  loan_duration: POSIXTime,
  interest_asset: AssetClass,
  interest_amount: Int,
  lender_address_hash: AddressHash,
}

pub type LoanInput {
  info: Info,
}

pub type LoanOutput {
  info: Info,
}

pub type LoanRefund {
  info: Info,
}

pub type ValidatorHash =
  Hash<Blake2b_224, Script>
