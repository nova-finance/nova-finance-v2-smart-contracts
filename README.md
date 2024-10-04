<!-- markdown-toc start - Don't edit this section. Run M-x markdown-toc-refresh-toc -->
# Table of Contents

- [Smart Lending](#smart-lending)
  - [Introduction](#introduction)
  - [High-Level Overview](#high-level-overview)
  - [Splitting Loan Offer Into Multiple UTxOs And Selecting Loan UTxOs To Fulfill A Loan](#splitting-loan-offer-into-multiple-utxos-and-selecting-loan-utxos-to-fulfill-a-loan)
  - [Smart Contract Technical Implementation](#smart-contract-technical-implementation)
    - [Get Loan](#get-loan)
    - [Repay Loan](#repay-loan)
    - [Cancel Loan Offer](#cancel-loan-offer)
    - [Liquidate Collateral](#liquidate-collateral)
    - [Collect Interest Payment](#collect-interest-payment)
- [Links](#links)
- [Special Shout Outs](#special-shout-outs)
 
# Smart Lending
## Introduction
Smart Lending introduces an order book model for decentralized lending for the first time. This model offers a unique twist which highlights the best traits of pooled lending and peered lending, which we believe has the potential to create the best lending experience on Cardano. Here’s a simple explanation of its key features and why it stands out.

* **Order Book Model**: Unlike typical DeFi platforms that use liquidity pools, Nova Finance V2 will use an order book model. This means lenders can place loan offers, and borrowers can take loans by either using partial offers or by putting together multiple offers. For instance, if a borrower wants to take a loan of $500, the system can fulfill this loan by partially using a $1000 offer leaving the rest available for others. Or a borrower could take a $2,000 loan for which the system puts two distinct $1,000 offers together. This offer selection is done algorithmically by the platform, so it works in a completely transparent and seamless manner for the end user. The specification for the selection algorithm will be made public once it’s completely defined.

* **Flexibility in Lending and Borrowing**: This fulfillment logic adds immense flexibility. Borrowers are not constrained to accept the fixed amounts of existing loan offers. They can borrow exactly what they need, making the process more efficient and tailored to individual requirements, while eliminating the need to use single UTxOs as in pooled lending, which natively generates contention.

* **Efficiency and Accessibility**: This lending model, utilizing multiple UTxOs, inherently mitigates transaction contention, thereby dispensing with the necessity for batchers, which are commonplace in pooled lending arrangements. Also, by being built on the Cardano blockchain, Nova Finance V2 benefits from low transaction fees and high transaction speeds. This makes the lending process more accessible and cost-effective for a broader range of users.

* **Innovative Approach to DeFi**: The order book model applied to lending is an innovative approach in the DeFi space. It blends elements of traditional finance (like order books) with the benefits of the eUTxO model of Cardano. This offers more competitive rates with the ability for loans to be filled based on partial or multiple existing offers, and can lead to more competitive interest rates, as lenders compete to have their funds borrowed. Additionally, this should encourage increased liquidity since loans can be partially filled, making funds more readily available.


## High-Level Overview
Lenders will have 4 actions they can perform:
* Create loan offers(Does not require any smart-script validations)
* Cancel loan offers
* Liquidate collaterals
* Collect interests

Lenders need to be guarantee of:
* For the amount of loan they gave out, there needs to be the correct amount of collateral locked up in the validator
and be able to liquidate it once the payment period has past
* They will collect the correct amount of interest for the loan they gave out

  
Borrowers will have 2 actions they can perform:
* Get loan
* Repay loan
  
Borrowers need to be guarantee of:
* They can get their collateral back once they pay back the correct amount of interest


The validators will be written in Aiken. There will be three validators:
* A loan validator that holds the original loan offer UTXOs, handling the validation of lenders canceling a loan offer and a borrower receiving a loan. When the borrower receives the loan, they will send their collaterals to be locked up at the collateral validator.
*  A collateral validator that will handle the validations of lenders liquidating the collateral and borrowers repaying the loan with interest. The loan and interest UTxO will be sent to the interest validator.
*  An interest validator that will handle the validations of the lenders getting back their original loan with interest 

### Splitting Loan Offer Into Multiple UTxOs And Selecting Loan UTxOs To Fulfill A Loan
When a lender submits a loan offer, we will split the initial loan into multiple small loans to be locked up at the loan validator. Each split-up UTxO will contain an equal amount of assets(or a multiplier of that amount). The amount may vary for different tokens. The parameters for each asset regarding the amount of asset in each loan UTxO will be disclosed openly through our GitHub repo. 


When a borrower searches for a loan, we will use a randomizing shuffle that gives priority to loan offers submitted earliest. We will assign weights for each UTxO, giving UTxO submitted first higher weights. The difference between the weights of consecutive transactions decreases as you move through each UTxO. 
```
const decayFactor = 0.5;
const weights = availableOffers.map((element, index) =>
  Math.exp(-index / decayFactor)
);
```
Lenders that submitted a large loan will have a higher chance of being selected, as they will contribute more UTxOs to the pool. 


A loan UTxO will contain the following datum 
```
pub type OfferLoanDatum {
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
```

## Smart Contract Technical Implementation

### Get Loan
#### High-Level Implementation
To validate a loan we will construct two lists of ValidateLoanInfo from the input loan UTxOs and output collateral UTxOs
```
pub type ValidateLoanInfo {
  loan_amount: Int,
  loan_asset: AssetClass,
  collateral_amount: Int,
  collateral_asset: AssetClass,
  interest_amount: Int,
  interest_asset: AssetClass,
  lender_address_hash: AddressHash,
  loan_duration: POSIXTime,
  lovelace_amount: Int,
}
```

We first need to fold the input loan UTxOs and remove duplicate lender address hashes. When there are duplicate lender address hashes, we will sum the collateral amount, loan amount, and interest amount, and keep everything else the same. The collateral amount and interest amount will be retrieved from the datum. The loan amount will be calculated by the amount of loan assets in the input loan UTxO. 

Since the loan offers are split into multiple small UTxOs, if the lender is giving a large loan offer in a native asset they will need to send a considerable amount of ADA to be locked up. The lovelace_amount ensures they get their ADA back as well as their interest and loan.


We will assume that the list of output collateral UTxO's datum contains a unique lender address hash. We will use a filter map function to construct a list of ValidateLoanInfo. The collateral amount will be calculated by grabbing the amount of collateral assets in the output UTXO. Everything else will be constructed from the datum of the collateral UTxOs. 


This is the datum for the collateral UTxO.
```
pub type CollateralDatum {
  loan_amount: Int,
  loan_asset: AssetClass,
  collateral_asset: AssetClass,
  interest_amount: Int,
  interest_asset: AssetClass,
  loan_duration: POSIXTime,
  lend_time: POSIXTime,
  lender_address_hash: AddressHash,
  total_interest_amount: Int,
  total_loan_amount: Int,
  borrower_address_hash: AddressHash,
}
```

The filter map function will only return a constructed ValidateLoanInfo if the following datum values are true.
* Lend time is within the transaction validity range 
* The total loan amount is equal to the total loan amount we got from the inputs
* The total interest amount is equal to the total interest amount we got from the inputs 
The latter two validations will be useful when paying back the loan.
  
Comparing the resulting two lists will validate that the datum in the collateral UTxO and the amount of collateral being locked up in the collateral validator are correct.

#### Quick Code Walkthrough
Get all inputs coming from the loan validator
```
let inputs_from_script_validator: List<Input> = get_inputs_from_script()
```


Fold through all the input loan UTxOs to construct a list of ValidateLoanInfo
```
let inputs_loan_info: List<ValidatLoanInfo> = get_inputs_loan_info()

fn get_inputs_loan_info(
  ...
) -> List<ValidateLoanInfo> {
   list.foldl(
     inputs_from_script,
     [],
     fn(input, inputs_loan) {
        ...
        when
          list.find(
            inputs_loan,
            fn(input_loan: ValidateLoanInfo) {
              ...
            },
        )
        is {
          Some(duplicate_loan) -> {
            ValidateLoanInfo {
              loan_amount: duplicate_loan.loan_amount + quantity_of(
                output.value,
                loan_offer_datum_typed.loan_asset.policy_id,
                loan_offer_datum_typed.loan_asset.asset_name,
              ),
              collateral_amount: loan_offer_datum_typed.collateral_amount + duplicate_loan.collateral_amount,
              interest_amount: loan_offer_datum_typed.interest_amount + duplicate_loan.interest_amount,
              ...
            }
          }
     }  None -> {
          let input_loan_info =
            ValidateLoanInfo {
              loan_amount: quantity_of(
                output.value,
                loan_offer_datum_typed.loan_asset.policy_id,
                loan_offer_datum_typed.loan_asset.asset_name,
              ),
              ...
            }
    }
}
```


Get all outputs going to the collateral validator 
```
let outputs_to_collateral_validator: List<Output> = find_script_outputs()    
```


Map through output collateral UTxOs to construct a list of ValidateLoanInfo
```
let outputs_collateral_info: List<ValidateLoanInfo> = get_outputs_collateral_info()

fn get_outputs_collateral_info(
  ...
) -> List<ValidateLoanInfo> {
  list.filter_map(
    validator_outputs,
    fn(output: Output) {
      ...
      let output_datum_valid = lend_time_valid && total_loan_amount_valid && total_interest_amount_valid
      if output_datum_valid {
        Some(
          ValidateLoanInfo {
            collateral_amount: quantity_of(
              output.value,
              collateral_datum_typed.collateral_asset.policy_id,
              collateral_datum_typed.collateral_asset.asset_name,
            ),
            ...
          }
        )
      } else {
        None
      }
    }
  )
}

```


Check if the two lists of ValidateLoanInfo match up 
```
let info_difference = list.difference(input_loan_info, outputs_collateral_info)
let info_matches = list.length(info_difference) == 0
let length_matches = list.length(input_loan_info) == list.length(outputs_collateral_info)
info_matches
```

### Repay Loan
#### High-Level Implementation
Repaying loan validation will be similar to grabbing a loan. We will construct two lists of ValidateRepayInfo from the input collateral UTxOs and output interest UTxOs. 
```
pub type ValidateRepayInfo {
  repay_loan_amount: Int,
  repay_loan_asset: AssetClass,
  repay_interest_amount: Int,
  repay_interest_asset: AssetClass,
  lender_address_hash: AddressHash,
}
```
The collateral validator will assume that the input collateral UTxOs and output interest UTxOs contain a unique lender address hash in the datum.


A filter map function will be used for the input collateral UTxOs. The datum in the inputs will be used to construct the value of lender address hash, loan amount, loan asset, repay interest amount, and repay interest asset. We can trust these values in the datum because we have already validated them in the loan validator. We will only return a constructed ValidateRepayInfo if the following validations are true: 
* The deadline to repay the loan has not passed, and the original loan borrower signed the transaction.
* The total loan amount and total repaid loan amount going to the interest validator need to equal the amount specified in the datum.
* The original borrower is signing the transaction
These checks ensure that the entire loan is being paid off not just parts of it, there is still time to pay off the loan, and preventing someone else other than the original borrower from getting the collateral.


The output interest UTxOs contain the loan asset and repay interest asset in the datum. We will map through each UTxO to find the amount of each asset it contains. The rest of the ValidateRepayInfo properties will be constructed from the datum in the output interest UTxO.

 
The resulting two lists of ValidateRepayInfo will validate that the borrower is repaying the correct amount to all the lenders and datum in the interest UTxO has not been corrupted. 

#### Quick Code Walkthrough
Get all inputs coming from the collateral validator 
```
let inputs_from_collateral_validator: List<Input> = get_inputs_from_script()
```


Get all outputs going to the interest validator
```
let outputs_to_interest_validator: List<Output> = find_script_outputs()
```


Get the total loan repaid amount and interest amount from the UTxOs going to the interest validator
```
pub type LoanAndInterestAmount {
  loan_amount: Int,
  interest_amount: Int,
}

let total_repay_amount: LoanAndInterestAmount = get_total_repay_loan_and_interest_amount()
```


Map through the input collateral UTxOs to construct a list of ValidateRepayInfo
```
let inputs_collateral_info: List<ValidateRepayInfo> = get_inputs_collateral_info()

fn get_inputs_collateral_info(
  ...
) -> List<ValidateRepayInfo> {
  list.filter_map(
    inputs_from_collateral_validator,
    fn(input_from_collateral_validator: Input) {
      ...
      let collateral_valid = total_loan_amount_valid && deadline_not_passed && signed_by_borrower && total_interest_amount_valid
     if collateral_valid {
       Some(ValidateRepayInfo ....)
     } else {
       None
     }
    }
  )
}
```


Map through the interest UTxOs to construct a list of ValidateRepayInfo
```
let outputs_interest_info: List<ValidateRepayInfo> = get_outputs_interest_info()

fn get_outputs_interest_info(
  outputs_to_interest_validator: List<Output>,
) -> List<ValidateRepayInfo> {
  list.map(
    outputs_to_interest_validator,
    fn(output: Output) {
      ...
      let loan_and_interest_amount: LoanAndInterestAmount = get_loan_and_interest_from_output(output)
      ValidateRepayInfo {
        repay_loan_amount: loan_and_interest_amount.loan_amount,
        repay_interest_amount: loan_and_interest_amount.interest_amount,
        ...
      }
    }
  )
}
```


Check if the two lists of ValidateRepayInfo match up 
```
let info_difference = list.difference(outputs_interest_info, inputs_collateral_info)
let info_matches = list.length(info_difference) == 0
let length_matches = list.length(outputs_interest_info) == list.length(inputs_collateral_info)
info_matches && length_matches
```

### Cancel Loan Offer
#### High-Level Implementation
To cancel a loan we need to make sure the original lender is signing the transaction. The original lender address hash is stored in the datum of the loan offer UTxO.

#### Quick Code Walkthrough
Check transaction is signed by the lender
```
let must_be_signed_by_lender =
  list.has(ctx.transaction.extra_signatories, datum.lender_address_hash)
must_be_signed_by_lender
```

### Liquidate Collateral
#### High-Level Implementation
To liquidate a collateral we need to first check that the repay period has expired and the original lender is signing the transaction. The collateral UTxOs contain the lend time, loan duration, and lender address hash in the datum. 

#### Quick Code Walkthrough
Check the deadline has passed and the transaction is signed by the lender
```
let must_be_signed_by_lender = list.has(ctx.transaction.extra_signatories, datum.lender_address_hash)
let deadline_passed = datum.loan_duration + datum.lend_time < utils.get_lower_bound(ctx.transaction.validity_range,)
must_be_signed_by_lender && deadline_passed
```

### Collect Interest Payment
#### High-Level Implementation
To cancel a loan we need to make sure the original lender is signing the transaction. The original lender address hash is stored in the datum of the interest UTxO.

#### Quick Code Walkthrough
Check transaction is signed by the lender
```
let must_be_signed_by_lender = list.has(ctx.transaction.extra_signatories, datum.lender_address_hash)
must_be_signed_by_lender
```


### Special Shout Outs
Special thanks to Keyan M's guidance, and open-sourced code from Anastasia Labs, Lenfi, and Sundae Labs <3
