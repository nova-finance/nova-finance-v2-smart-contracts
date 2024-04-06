use aiken/interval.{Finite}
use aiken/transaction.{ValidityRange}
use aiken/transaction/credential.{
  Address, Inline, ScriptCredential, VerificationKeyCredential,
}

pub fn scripthash_address(scripthash: ByteArray, stake_hash: ByteArray) {
  Address {
    payment_credential: ScriptCredential(scripthash),
    stake_credential: Some(Inline(VerificationKeyCredential(stake_hash))),
  }
}

pub fn get_lower_bound(range: ValidityRange) -> Int {
  expect Finite(lower_bound) = range.lower_bound.bound_type
  lower_bound
}
