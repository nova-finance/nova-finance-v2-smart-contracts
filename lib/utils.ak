use aiken/interval.{Finite}
use aiken/list
use aiken/option
use aiken/transaction.{
  InlineDatum, Input, Output, OutputReference, ScriptContext, ValidityRange,
}
use aiken/transaction/credential.{
  Address, Inline, ScriptCredential, VerificationKeyCredential,
}
use aiken/transaction/value.{Value, quantity_of}
use types.{
  AddressHash, AssetClass, CollateralDatum, Info, LoanInput, LoanOfferDatum,
  LoanOutput, ValidatorHash,
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

pub fn get_output_collateral_info(
  script_outputs: List<Output>,
  total_loan_amount: Int,
  borrower_address_hash: AddressHash,
  ctx: ScriptContext,
) -> List<LoanOutput> {
  list.filter_map(
    script_outputs,
    fn(output: Output) {
      expect InlineDatum(collateral_datum) = output.datum
      expect collateral_datum_typed: CollateralDatum = collateral_datum

      let borrower_address_valid =
        collateral_datum_typed.borrower_address_hash == borrower_address_hash
      let tx_id_valid = collateral_datum_typed.tx_id == ctx.transaction.id
      let lend_time_valid =
        collateral_datum_typed.lend_time == get_lower_bound(
          ctx.transaction.validity_range,
        )
      let total_loan_amount_valid =
        collateral_datum_typed.total_loan_amount == total_loan_amount

      let output_datum_valid =
        borrower_address_valid && tx_id_valid && lend_time_valid && total_loan_amount_valid

      if output_datum_valid {
        let info =
          Info {
            loan_amount: collateral_datum_typed.loan_amount,
            loan_asset: collateral_datum_typed.loan_asset,
            collateral_amount: quantity_of(
              output.value,
              collateral_datum_typed.collateral_asset.policy_id,
              collateral_datum_typed.collateral_asset.asset_name,
            ),
            collateral_asset: collateral_datum_typed.collateral_asset,
            interest_amount: collateral_datum_typed.interest_amount,
            interest_asset: collateral_datum_typed.interest_asset,
            lender_address_hash: collateral_datum_typed.lender_address_hash,
            loan_duration: collateral_datum_typed.loan_duration,
          }

        let output_collateral_info: LoanOutput = LoanOutput { info }
        Some(output_collateral_info)
      } else {
        None
      }
    },
  )
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

pub fn get_expected_collateral_from_inputs(
  inputs_from_script: List<Input>,
) -> List<LoanInput> {
  list.foldl(
    inputs_from_script,
    [],
    fn(input, inputs_loan) {
      let output: Output = input.output
      expect InlineDatum(loan_offer_datum) = output.datum
      expect loan_offer_datum_typed: LoanOfferDatum = loan_offer_datum

      when
        list.find(
          inputs_loan,
          fn(input_loan: LoanInput) {
            input_loan.info.lender_address_hash == loan_offer_datum_typed.lender_address_hash
          },
        )
      is {
        Some(duplicate_loan) -> {
          let new_input_loan_info =
            Info {
              loan_amount: duplicate_loan.info.loan_amount + quantity_of(
                output.value,
                loan_offer_datum_typed.loan_asset.policy_id,
                loan_offer_datum_typed.loan_asset.asset_name,
              ),
              loan_asset: loan_offer_datum_typed.loan_asset,
              collateral_amount: loan_offer_datum_typed.collateral_amount + duplicate_loan.info.collateral_amount,
              collateral_asset: loan_offer_datum_typed.collateral_asset,
              interest_amount: loan_offer_datum_typed.interest_amount + duplicate_loan.info.interest_amount,
              interest_asset: loan_offer_datum_typed.interest_asset,
              lender_address_hash: loan_offer_datum_typed.lender_address_hash,
              loan_duration: loan_offer_datum_typed.loan_duration,
            }

          let new_input_loan = LoanInput { info: new_input_loan_info }

          let removed_duplicate_collateral_list =
            list.filter(
              inputs_loan,
              fn(input_loan: LoanInput) {
                input_loan.info.lender_address_hash != loan_offer_datum_typed.lender_address_hash
              },
            )

          [new_input_loan, ..removed_duplicate_collateral_list]
        }
        None -> {
          let input_loan_info =
            get_info_from_loan_offer(loan_offer_datum_typed, output.value)

          let input_loan = LoanInput { info: input_loan_info }
          [input_loan, ..inputs_loan]
        }
      }
    },
  )
}

pub fn get_refund_info(script_outputs: List<Output>) -> List<Info> {
  list.map(
    script_outputs,
    fn(output: Output) {
      expect InlineDatum(loan_offer_datum) = output.datum
      expect loan_offer_datum_typed: LoanOfferDatum = loan_offer_datum
      let info = get_info_from_loan_offer(loan_offer_datum_typed, output.value)
      info
    },
  )
}

pub fn get_info_from_loan_offer(
  loan_offer_datum: LoanOfferDatum,
  value: Value,
) -> Info {
  Info {
    loan_amount: quantity_of(
      value,
      loan_offer_datum.loan_asset.policy_id,
      loan_offer_datum.loan_asset.asset_name,
    ),
    loan_asset: loan_offer_datum.loan_asset,
    collateral_amount: loan_offer_datum.collateral_amount,
    collateral_asset: loan_offer_datum.collateral_asset,
    interest_amount: loan_offer_datum.interest_amount,
    interest_asset: loan_offer_datum.interest_asset,
    lender_address_hash: loan_offer_datum.lender_address_hash,
    loan_duration: loan_offer_datum.loan_duration,
  }
}

pub fn info_matches(
  input_loan_info: List<Info>,
  outputs_collateral_info: List<Info>,
) -> Bool {
  let info_difference =
    list.difference(input_loan_info, outputs_collateral_info)

  let info_matches = list.length(info_difference) == 0
  info_matches
}
