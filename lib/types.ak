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
  loan_amount: Int,
  loan_asset: AssetClass,
  collateral_amount: Int,
  collateral_asset: AssetClass,
  interest_amount: Int,
  interest_asset: AssetClass,
  interest_percent: Int,
  loan_duration: POSIXTime,
  lender_address_hash: AddressHash,
}

pub type CollateralDatum {
  loan_amount: Int,
  loan_asset: AssetClass,
  collateral_amount: Int,
  collateral_asset: AssetClass,
  interest_amount: Int,
  interest_asset: AssetClass,
  loan_duration: POSIXTime,
  lend_time: POSIXTime,
  lender_address_hash: AddressHash,
  total_interest_amount: Int,
  total_loan_amount: Int,
  borrower_address_hash: AddressHash,
  tx_id: TransactionId,
}

pub type InterestDatum {
  lender_address_hash: AddressHash,
  repay_loan_amount: Int,
  repay_loan_asset: AssetClass,
  repay_interest_amount: Int,
  repay_interest_asset: AssetClass,
}

pub type AddressAndValue {
  address_hash: AddressHash,
  value: Value,
}

pub type Info {
  loan_amount: Int,
  loan_asset: AssetClass,
  collateral_amount: Int,
  collateral_asset: AssetClass,
  interest_amount: Int,
  interest_asset: AssetClass,
  lender_address_hash: AddressHash,
  loan_duration: POSIXTime,
}

pub type ValidateRepayInfo {
  lender_address_hash: AddressHash,
  repay_loan_amount: Int,
  repay_loan_asset: AssetClass,
  repay_interest_amount: Int,
  repay_interest_asset: AssetClass,
}

pub type ValidatorHash =
  Hash<Blake2b_224, Script>

pub type LoanAndInterestAmount {
  loan_amount: Int,
  interest_amount: Int,
}
