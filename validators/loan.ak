use aiken/list
use aiken/transaction.{
  Input, Output, OutputReference, ScriptContext, Spend, find_script_outputs,
}
use aiken/transaction/credential.{Address}
use types.{AddressAndValue, ExpectedCollateral, LoanOfferDatum}
use utils.{
  get_expected_collateral_from_inputs, get_output_collateral_info,
  get_own_validator_inputs,
}

type LoanRedeemer {
  GetLoan(Address)
  CancelRequest
}

fn collateral_output_is_valid(
  ctx: ScriptContext,
  datum: LoanOfferDatum,
  collateral_script_hash: ByteArray,
  contract_stake_hash: ByteArray,
  output_ref: OutputReference,
  borrower_address_hash: Address,
) -> Bool {
  // Collateral value is correct
  let script_outputs: List<Output> =
    find_script_outputs(ctx.transaction.outputs, collateral_script_hash)

  let output_address_and_value: List<ExpectedCollateral> =
    get_output_collateral_info(script_outputs)

  let all_inputs_from_script: List<Input> =
    get_own_validator_inputs(ctx, output_ref, contract_stake_hash)

  let input_expected_collateral: List<ExpectedCollateral> =
    get_expected_collateral_from_inputs(all_inputs_from_script)

  let collateral_matches =
    list.difference(output_address_and_value, input_expected_collateral)

  // Check that the expected collateral from inputs matches the actual collateral output
  list.length(collateral_matches) == 0
}

validator(collateral_script_hash: ByteArray, contract_stake_hash: ByteArray) {
  fn loan(
    datum: LoanOfferDatum,
    redeemer: LoanRedeemer,
    ctx: ScriptContext,
  ) -> Bool {
    when redeemer is {
      // todo
      GetLoan(borrower_address_hash) ->
        when ctx.purpose is {
          Spend(output_ref) ->
            collateral_output_is_valid(
              ctx,
              datum,
              collateral_script_hash,
              contract_stake_hash,
              output_ref,
              borrower_address_hash,
            )

          _ -> False
        }

      CancelRequest -> {
        let must_be_signed_by_lender =
          list.has(ctx.transaction.extra_signatories, datum.lender_address_hash)
        must_be_signed_by_lender
      }
    }
  }
}
