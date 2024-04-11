use aiken/interval.{Finite}
use aiken/list
use aiken/option
use aiken/transaction.{
  Input, Output, OutputReference, ScriptContext, ValidityRange,
}
use aiken/transaction/credential.{
  Address, Inline, ScriptCredential, VerificationKeyCredential,
}
use types.{ValidatorHash}

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

pub fn own_validator_script_address_hash(
  inputs: List<Input>,
  output_reference: OutputReference,
) -> Option<ValidatorHash> {
  inputs
    |> list.find(fn(input) { input.output_reference == output_reference })
    |> option.map(fn(v) { v.output })
    |> option.map(fn(v) { v.address })
    |> option.map(fn(v) { v.payment_credential })
    |> option.map(
        fn(v) {
          when v is {
            ScriptCredential(hash) -> Some(hash)
            _ -> None
          }
        },
      )
    |> option.flatten()
}

pub fn get_own_validator_address(
  ctx: ScriptContext,
  output_reference: OutputReference,
  stake_hash,
) -> Address {
  expect Some(validator_hash) =
    own_validator_script_address_hash(ctx.transaction.inputs, output_reference)
  scripthash_address(validator_hash, stake_hash)
}

pub fn get_own_validator_inputs(
  ctx: ScriptContext,
  output_reference: OutputReference,
  stake_hash: ByteArray,
) -> List<Input> {
  let script_own_address =
    get_own_validator_address(ctx, output_reference, stake_hash)

  // Get all inputs from the transaction
  list.filter(
    ctx.transaction.inputs,
    fn(input) { input.output.address == script_own_address },
  )
}
