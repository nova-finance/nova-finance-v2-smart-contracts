use aiken/builtin
use aiken/dict
use aiken/interval.{Finite}
use aiken/list
use aiken/transaction.{Input, Output, OutputReference, ValidityRange}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKeyCredential,
}
use aiken/transaction/value.{PolicyId, Value, flatten, tokens}

pub fn get_lower_bound(range: ValidityRange) -> Int {
  expect Finite(lower_bound) = range.lower_bound.bound_type
  lower_bound
}

pub fn get_inputs_from_script(
  inputs: List<Input>,
  script_hash: ByteArray,
) -> List<Input> {
  inputs
    |> list.filter(
        fn(input) {
          when input.output.address.payment_credential is {
            ScriptCredential(addr_script_hash) ->
              script_hash == addr_script_hash
            VerificationKeyCredential(_) -> False
          }
        },
      )
}

pub fn validate_token_mint(
  mints: Value,
  expected_minting: (PolicyId, ByteArray, Int),
) -> Bool {
  when list.find(flatten(mints), fn(mint) { mint == expected_minting }) is {
    Some(_) -> only_one_token_in_policy_minted(mints, expected_minting)
    None -> False
  }
}

// Make sure only one token is minted from the asset tuple
fn only_one_token_in_policy_minted(mints, expected_minting) {
  let (policy_id, _, _) = expected_minting
  let policy_id: PolicyId = policy_id
  // Check for the policy mints
  list.length(dict.keys(tokens(mints, policy_id))) == 1
  // Total count of minted unique tokens with policy is 1
}

pub fn resolve_output_reference(
  inputs: List<Input>,
  output_ref: OutputReference,
) -> Output {
  expect [input, ..] = inputs

  if input.output_reference == output_ref {
    input.output
  } else {
    resolve_output_reference(builtin.tail_list(inputs), output_ref)
  }
}
