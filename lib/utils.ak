use aiken/transaction/credential.{
  Address, Inline, ScriptCredential, VerificationKeyCredential,
}

pub fn scripthash_address(scripthash: ByteArray, stake_hash: ByteArray) {
  Address {
    payment_credential: ScriptCredential(scripthash),
    stake_credential: Some(Inline(VerificationKeyCredential(stake_hash))),
  }
}
