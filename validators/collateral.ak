use aiken/dict
use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Output, ScriptContext, Spend, Transaction, ValidityRange,
  WithdrawFrom, find_script_outputs,
}
use aiken/transaction/credential.{Inline, ScriptCredential}
use aiken/transaction/value.{
  AssetName, from_minted_value, lovelace_of, quantity_of,
}
use types.{
  AddressHash, AssetClass, CollateralDatum, InterestDatum, LoanAndInterestAmount,
  ValidateRepayInfo,
}
use utils.{get_inputs_from_script, resolve_output_reference}

type CollateralRedeemer {
  LiquidateCollateral(AssetName)
  RepayLoan(Int)
}

type Redeemer {
  action: CollateralRedeemer,
}

pub fn get_input_lovelace_amount(
  output: Output,
  loan_asset: AssetClass,
  amount: Int,
) -> Int {
  if loan_asset.policy_id == "" {
    lovelace_of(output.value) + amount
  } else {
    lovelace_of(output.value)
  }
}

fn get_loan_and_interest_from_output(output: Output) -> LoanAndInterestAmount {
  expect InlineDatum(interest_datum) = output.datum
  expect interest_datum_typed: InterestDatum = interest_datum
  let loan_and_interest_asset_same =
    interest_datum_typed.repay_loan_asset == interest_datum_typed.repay_interest_asset

  when loan_and_interest_asset_same is {
    True -> {
      let total_asset_amount =
        quantity_of(
          output.value,
          interest_datum_typed.repay_loan_asset.policy_id,
          interest_datum_typed.repay_loan_asset.asset_name,
        )

      LoanAndInterestAmount {
        loan_amount: total_asset_amount - interest_datum_typed.repay_interest_amount,
        interest_amount: total_asset_amount - interest_datum_typed.repay_loan_amount,
      }
    }

    False ->
      LoanAndInterestAmount {
        loan_amount: quantity_of(
          output.value,
          interest_datum_typed.repay_loan_asset.policy_id,
          interest_datum_typed.repay_loan_asset.asset_name,
        ),
        interest_amount: quantity_of(
          output.value,
          interest_datum_typed.repay_interest_asset.policy_id,
          interest_datum_typed.repay_interest_asset.asset_name,
        ),
      }
  }
}

fn get_total_repay_loan_and_interest_amount(
  outputs_to_interest_validator: List<Output>,
) -> LoanAndInterestAmount {
  list.foldl(
    outputs_to_interest_validator,
    LoanAndInterestAmount { loan_amount: 0, interest_amount: 0 },
    fn(output: Output, acc: LoanAndInterestAmount) {
      let loan_and_interest_amount = get_loan_and_interest_from_output(output)

      LoanAndInterestAmount {
        loan_amount: acc.loan_amount + loan_and_interest_amount.loan_amount,
        interest_amount: acc.interest_amount + loan_and_interest_amount.interest_amount,
      }
    },
  )
}

fn get_inputs_collateral_info(
  inputs_from_collateral_validator: List<Input>,
  total_repaid_amount: LoanAndInterestAmount,
  validity_range: ValidityRange,
  signatures: List<AddressHash>,
) -> List<ValidateRepayInfo> {
  list.filter_map(
    inputs_from_collateral_validator,
    fn(input_from_collateral_validator: Input) {
      expect InlineDatum(collateral_datum) =
        input_from_collateral_validator.output.datum
      expect collateral_datum_typed: CollateralDatum = collateral_datum

      let total_loan_amount_valid =
        total_repaid_amount.loan_amount == collateral_datum_typed.total_loan_amount
      let total_interest_amount_valid =
        total_repaid_amount.interest_amount == collateral_datum_typed.total_interest_amount
      let deadline_not_passed =
        collateral_datum_typed.lend_time + collateral_datum_typed.loan_duration > utils.get_lower_bound(
          validity_range,
        )
      let signed_by_borrower =
        list.has(signatures, collateral_datum_typed.borrower_address_hash)
      let collateral_valid =
        deadline_not_passed && signed_by_borrower && total_interest_amount_valid && total_loan_amount_valid

      if collateral_valid {
        let input_lovelace_amount =
          get_input_lovelace_amount(
            input_from_collateral_validator.output,
            collateral_datum_typed.loan_asset,
            collateral_datum_typed.interest_amount,
          )

        Some(
          ValidateRepayInfo {
            repay_loan_amount: collateral_datum_typed.total_loan_amount,
            repay_loan_asset: collateral_datum_typed.loan_asset,
            repay_interest_amount: collateral_datum_typed.total_interest_amount,
            repay_interest_asset: collateral_datum_typed.interest_asset,
            lender_address_hash: collateral_datum_typed.lender_address_hash,
            lovelace_amount: input_lovelace_amount,
          },
        )
      } else {
        None
      }
    },
  )
}

fn get_outputs_interest_info(
  outputs_to_interest_validator: List<Output>,
) -> List<ValidateRepayInfo> {
  list.map(
    outputs_to_interest_validator,
    fn(output: Output) {
      expect InlineDatum(interest_datum) = output.datum
      expect interest_datum_typed: InterestDatum = interest_datum

      let loan_and_interest_amount: LoanAndInterestAmount =
        get_loan_and_interest_from_output(output)
      ValidateRepayInfo {
        repay_loan_amount: loan_and_interest_amount.loan_amount,
        repay_loan_asset: interest_datum_typed.repay_loan_asset,
        repay_interest_amount: loan_and_interest_amount.interest_amount,
        repay_interest_asset: interest_datum_typed.repay_interest_asset,
        lender_address_hash: interest_datum_typed.lender_address_hash,
        lovelace_amount: lovelace_of(output.value),
      }
    },
  )
}

fn interest_payment_is_valid(
  ctx: ScriptContext,
  interest_validator_hash: ByteArray,
  collateral_validator_hash: ByteArray,
) -> Bool {
  let validity_range: ValidityRange = ctx.transaction.validity_range

  let signatures: List<AddressHash> = ctx.transaction.extra_signatories

  let outputs_to_interest_validator: List<Output> =
    find_script_outputs(ctx.transaction.outputs, interest_validator_hash)

  let inputs_from_collateral_validator: List<Input> =
    get_inputs_from_script(ctx.transaction.inputs, collateral_validator_hash)

  let total_repay_amount: LoanAndInterestAmount =
    get_total_repay_loan_and_interest_amount(outputs_to_interest_validator)

  let inputs_collateral_info: List<ValidateRepayInfo> =
    get_inputs_collateral_info(
      inputs_from_collateral_validator,
      total_repay_amount,
      validity_range,
      signatures,
    )
  let outputs_interest_info: List<ValidateRepayInfo> =
    get_outputs_interest_info(outputs_to_interest_validator)

  let info_difference =
    list.difference(outputs_interest_info, inputs_collateral_info)
  let info_matches = list.length(info_difference) == 0

  let length_matches =
    list.length(outputs_interest_info) == list.length(inputs_collateral_info)
  info_matches && length_matches
}

fn liquidate_collateral_valid(
  ctx: ScriptContext,
  datum: CollateralDatum,
  oracle_tn: AssetName,
) -> Bool {
  let must_be_signed_by_lender =
    list.has(ctx.transaction.extra_signatories, datum.lender_address_hash)
  let deadline_passed =
    datum.loan_duration + datum.lend_time < utils.get_lower_bound(
      ctx.transaction.validity_range,
    )

  let oracle_token_minted =
    utils.validate_token_mint(
      from_minted_value(ctx.transaction.mint),
      (datum.liquidation_policy, oracle_tn, 1),
    )

  must_be_signed_by_lender && deadline_passed || oracle_token_minted
}

validator(interest_validator_hash: ByteArray) {
  fn spend(
    datum: CollateralDatum,
    redeemer: Redeemer,
    ctx: ScriptContext,
  ) -> Bool {
    when redeemer.action is {
      LiquidateCollateral(oracle_tn) ->
        liquidate_collateral_valid(ctx, datum, oracle_tn)

      RepayLoan(_) -> {
        expect ScriptContext { transaction: tx, purpose: Spend(own_ref) } = ctx

        let Transaction { inputs, withdrawals, .. } = tx

        let Output { address: own_addr, .. } =
          resolve_output_reference(inputs, own_ref)

        let own_withdrawal = Inline(own_addr.payment_credential)

        dict.has_key(withdrawals, own_withdrawal)
      }
    }
  }

  fn withdraw(_redeemer: Int, ctx: ScriptContext) {
    expect ScriptContext { transaction: _tx, purpose: WithdrawFrom(stake_cred) } =
      ctx

    expect Inline(ScriptCredential(collateral_validator_hash)) = stake_cred
    interest_payment_is_valid(
      ctx,
      interest_validator_hash,
      collateral_validator_hash,
    )
  }
}
