;; Test script for NFT-Collateralized Lending Protocol
;; Run with `clarity-cli test /path/to/test-script.clar`

;; Import the main contract
(contract-call? .nft-lending-protocol initialize 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)

;; Test utilities
(define-constant test-address-1 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
(define-constant test-address-2 'ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG)
(define-constant test-address-3 'ST2JHG361ZXG51QTKY2NQCVBPPRRE2KZB1HR05NNC)
(define-constant test-appraiser-1 'ST2REHHS5J3CERCRBEPMGH7921Q6PYKAADT7JP2VB)
(define-constant test-appraiser-2 'ST3AM1A56AK2C1XAFJ4115ZSV26EB49BVQ10MGCS0)
(define-constant test-appraiser-3 'ST3NBRSFKX28FQ2ZJ1MAKX58HKHSDGNV5N7R21XCP)

(define-constant test-nft-contract 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.test-nft)

;; Helper for testing expected results
(define-private (test-result (actual (response bool uint)) (expected-error (optional uint)))
  (if (is-some expected-error)
    (and (is-err actual) (is-eq (unwrap-err actual) (unwrap-panic expected-error)))
    (is-ok actual)
  )
)

;; Test setup
(print "Setting up test environment...")

;; Test 1: Register a new collection
(print "Test 1: Register a new collection")
(let ((result (contract-call? .nft-lending-protocol register-collection 
               "test-collection-1" 
               test-nft-contract
               "https://example.com/api/nft/"
               u5000  ;; 50% max LTV
               u500   ;; 5% min interest rate
               u2000  ;; 20% max interest rate
               "linear"
               (list "Common" "Uncommon" "Rare" "Epic" "Legendary")
               u1000000 ;; Min value 1M tokens
               u100000000 ;; Max value 100M tokens
               )))
  (asserts! (is-ok result) (err "Failed to register collection"))
  (print "✓ Collection registered successfully")
)
;; Test 2: Authorize appraisers
(print "Test 2: Authorize appraisers")
(let ((result-1 (contract-call? .nft-lending-protocol authorize-appraiser
                test-appraiser-1
                (list "test-collection-1")))
      (result-2 (contract-call? .nft-lending-protocol authorize-appraiser
                test-appraiser-2
                (list "test-collection-1")))
      (result-3 (contract-call? .nft-lending-protocol authorize-appraiser
                test-appraiser-3
                (list "test-collection-1"))))
  (asserts! (and (is-ok result-1) (is-ok result-2) (is-ok result-3)) 
            (err "Failed to authorize appraisers"))
  (print "✓ Appraisers authorized successfully")
)

;; Test 3: Test appraisal workflow
(print "Test 3: Testing appraisal workflow")

;; 3.1 Request an appraisal
(print "3.1: Request an appraisal")
(let ((result (as-contract (contract-call? .nft-lending-protocol request-appraisal
                          "test-collection-1"
                          u1))))
  (asserts! (is-ok result) (err "Failed to request appraisal"))
  (let ((request-id (unwrap-panic result)))
    (print (concat "✓ Appraisal requested with ID: " (to-string request-id)))
    
    ;; 3.2 Submit appraisals from all appraisers
    (print "3.2: Submit appraisals")
    (let ((result-1 (contract-call? .nft-lending-protocol submit-appraisal request-id u10000000 tx-sender test-appraiser-1))
          (result-2 (contract-call? .nft-lending-protocol submit-appraisal request-id u11000000 tx-sender test-appraiser-2))
          (result-3 (contract-call? .nft-lending-protocol submit-appraisal request-id u12000000 tx-sender test-appraiser-3)))
      (asserts! (and (is-ok result-1) (is-ok result-2) (is-ok result-3)) 
                (err "Failed to submit appraisals"))
      (print "✓ Appraisals submitted successfully")
      
      ;; 3.3 Check if appraisal was finalized
      (print "3.3: Verify appraisal finalization")
      (let ((appraisal-request (contract-call? .nft-lending-protocol get-appraisal-request request-id)))
        (asserts! (is-ok appraisal-request) (err "Failed to get appraisal request"))
        (let ((request-data (unwrap-panic appraisal-request)))
          (asserts! (is-eq (get status request-data) "completed") 
                    (err "Appraisal was not finalized"))
          (asserts! (is-some (get final-value request-data)) 
                    (err "Appraisal has no final value"))
          (print (concat "✓ Appraisal finalized with value: " 
                 (to-string (unwrap-panic (get final-value request-data)))))
        )
      )
    )
  )
)

;; Test 4: Apply for a loan
(print "Test 4: Apply for a loan")
(let ((result (contract-call? .nft-lending-protocol apply-for-loan
              "test-collection-1"
              u1
              u5000000  ;; 5M tokens (50% of appraised value)
              u1440     ;; 10 day duration (144 blocks per day)
              )))
  (asserts! (is-ok result) (err "Failed to apply for loan"))
  (let ((loan-id (unwrap-panic result)))
    (print (concat "✓ Loan created with ID: " (to-string loan-id)))
    
    ;; 4.1 Check loan details
    (print "4.1: Verify loan details")
    (let ((loan-details (contract-call? .nft-lending-protocol get-loan loan-id)))
      (asserts! (is-ok loan-details) (err "Failed to get loan details"))
      (let ((loan-data (unwrap-panic loan-details)))
        (asserts! (is-eq (get state loan-data) u0) (err "Loan state is not active"))
        (asserts! (is-eq (get borrower loan-data) tx-sender) 
                  (err "Loan borrower doesn't match"))
        (print (concat "✓ Loan verified with amount: " 
               (to-string (get loan-amount loan-data))
               " and interest rate: "
               (to-string (get interest-rate loan-data))))
      )
    )
  )
)

;; Test 5: Partial loan repayment
(print "Test 5: Partial loan repayment")
(let ((loan-id u1)
      (repay-amount u1000000)) ;; 1M tokens
  (let ((result (contract-call? .nft-lending-protocol repay-loan loan-id repay-amount)))
    (asserts! (is-ok result) (err "Failed to repay loan"))
    (print "✓ Partial repayment successful")
    
    ;; 5.1 Check updated loan details
    (print "5.1: Verify updated loan details")
    (let ((loan-details (contract-call? .nft-lending-protocol get-loan loan-id)))
      (asserts! (is-ok loan-details) (err "Failed to get loan details"))
      (let ((loan-data (unwrap-panic loan-details)))
        (asserts! (> (get repaid-amount loan-data) u0) 
                  (err "Repaid amount was not updated"))
        (print (concat "✓ Loan updated with repaid amount: " 
               (to-string (get repaid-amount loan-data))))
      )
    )
  )
)

;; Test 6: Full loan repayment
(print "Test 6: Full loan repayment")
(let ((loan-id u1))
  (let ((loan-details (contract-call? .nft-lending-protocol get-loan loan-id)))
    (asserts! (is-ok loan-details) (err "Failed to get loan details"))
    (let ((loan-data (unwrap-panic loan-details))
          (remaining (get remaining-amount loan-data)))
      (let ((result (contract-call? .nft-lending-protocol repay-loan loan-id remaining)))
        (asserts! (is-ok result) (err "Failed to repay loan fully"))
        (print "✓ Full repayment successful")
        
        ;; 6.1 Check loan is marked as repaid
        (print "6.1: Verify loan is marked as repaid")
        (let ((updated-loan (contract-call? .nft-lending-protocol get-loan loan-id)))
          (asserts! (is-ok updated-loan) (err "Failed to get updated loan details"))
          (let ((updated-data (unwrap-panic updated-loan)))
            (asserts! (is-eq (get state updated-data) u1) 
                      (err "Loan state is not marked as repaid"))
            (print "✓ Loan successfully marked as repaid")
            
            ;; 6.2 Verify NFT has been returned to borrower
            (print "6.2: Verify NFT returned to borrower")
            (let ((collateral-owner (contract-call? .nft-lending-protocol get-nft-owner
                                    "test-collection-1" u1)))
              (asserts! (is-ok collateral-owner) (err "Failed to get collateral owner"))
              (asserts! (is-eq (unwrap-panic collateral-owner) tx-sender) 
                        (err "NFT was not returned to borrower"))
              (print "✓ NFT successfully returned to borrower")
            )
          )
        )
      )
    )
  )
)

;; Test 7: Test liquidation trigger
(print "Test 7: Test liquidation trigger")
;; First create a new loan with high LTV
(let ((result (contract-call? .nft-lending-protocol apply-for-loan
              "test-collection-1"
              u2  ;; Different NFT
              u6000000  ;; 6M tokens (60% of appraised value)
              u1440     ;; 10 day duration
              )))
  (asserts! (is-ok result) (err "Failed to create loan for liquidation test"))
  (let ((loan-id (unwrap-panic result)))
    (print (concat "✓ Created loan ID " (to-string loan-id) " for liquidation test"))
    
    ;; 7.1 Force decrease in collateral value
    (print "7.1: Force decrease in collateral value")
    (let ((request-result (as-contract (contract-call? .nft-lending-protocol request-appraisal
                                      "test-collection-1" u2))))
      (asserts! (is-ok request-result) (err "Failed to request reappraisal"))
      (let ((request-id (unwrap-panic request-result)))
        ;; Submit much lower appraisals to trigger liquidation
        (let ((result-1 (contract-call? .nft-lending-protocol submit-appraisal request-id u7000000 tx-sender test-appraiser-1))
              (result-2 (contract-call? .nft-lending-protocol submit-appraisal request-id u7100000 tx-sender test-appraiser-2))
              (result-3 (contract-call? .nft-lending-protocol submit-appraisal request-id u7200000 tx-sender test-appraiser-3)))
          (asserts! (and (is-ok result-1) (is-ok result-2) (is-ok result-3)) 
                    (err "Failed to submit lower appraisals"))
          (print "✓ Submitted lower appraisals to trigger liquidation")
          
          ;; 7.2 Check if loan is liquidatable
          (print "7.2: Check if loan is liquidatable")
          (let ((check-result (contract-call? .nft-lending-protocol check-liquidation-status loan-id)))
            (asserts! (is-ok check-result) (err "Failed to check liquidation status"))
            (let ((status (unwrap-panic check-result)))
              (asserts! status (err "Loan is not marked as liquidatable"))
              (print "✓ Loan is correctly marked as liquidatable")
              
              ;; 7.3 Trigger liquidation
              (print "7.3: Trigger liquidation")
              (let ((liquidate-result (contract-call? .nft-lending-protocol liquidate-loan loan-id)))
                (asserts! (is-ok liquidate-result) (err "Failed to liquidate loan"))
                (let ((auction-id (unwrap-panic liquidate-result)))
                  (print (concat "✓ Loan liquidated with auction ID: " (to-string auction-id)))
                  
                  ;; 7.4 Check auction details
                  (print "7.4: Verify auction details")
                  (let ((auction-details (contract-call? .nft-lending-protocol get-auction auction-id)))
                    (asserts! (is-ok auction-details) (err "Failed to get auction details"))
                    (let ((auction-data (unwrap-panic auction-details)))
                      (asserts! (is-eq (get state auction-data) u0) 
                                (err "Auction state is not active"))
                      (asserts! (is-eq (get loan-id auction-data) loan-id) 
                                (err "Auction loan ID doesn't match"))
                      (print "✓ Auction verified and is active")
                    )
                  )
                )
              )
            )
          )
        )
      )
    )
  )
)
;; Test 8: Test auction bidding
(print "Test 8: Test auction bidding")
(let ((auction-id u1))
  ;; 8.1 Place a bid
  (print "8.1: Place a bid")
  (let ((bid-result (contract-call? .nft-lending-protocol place-bid 
                    auction-id
                    u5000000  ;; 5M tokens
                    )))
    (asserts! (is-ok bid-result) (err "Failed to place bid"))
    (print "✓ Bid placed successfully")
    
    ;; 8.2 Place a higher bid from another account
    (print "8.2: Place a higher bid")
    (let ((higher-bid-result (contract-call? .nft-lending-protocol place-bid 
                            auction-id
                            u5500000  ;; 5.5M tokens
                            tx-sender test-address-2)))
      (asserts! (is-ok higher-bid-result) (err "Failed to place higher bid"))
      (print "✓ Higher bid placed successfully")
      
      ;; 8.3 Verify current highest bidder
      (print "8.3: Verify highest bidder")
      (let ((auction-details (contract-call? .nft-lending-protocol get-auction auction-id)))
        (asserts! (is-ok auction-details) (err "Failed to get auction details"))
        (let ((auction-data (unwrap-panic auction-details)))
          (asserts! (is-eq (unwrap-panic (get current-bidder auction-data)) test-address-2) 
                    (err "Highest bidder is incorrect"))
          (asserts! (is-eq (get current-bid auction-data) u5500000) 
                    (err "Highest bid amount is incorrect"))
          (print "✓ Highest bidder verified correctly")
        )
      )
    )
  )
)

;; Test 9: Test auction settlement
(print "Test 9: Test auction settlement")
(let ((auction-id u1))
  ;; 9.1 Force auction to end
  (print "9.1: Force auction to end")
  ;; This would typically be done by advancing the block height
  ;; For our test, we'll use a force-end function if available
  (let ((end-result (contract-call? .nft-lending-protocol force-end-auction auction-id)))
    (asserts! (is-ok end-result) (err "Failed to end auction"))
    (print "✓ Auction ended successfully")
    
    ;; 9.2 Settle auction
    (print "9.2: Settle auction")
    (let ((settle-result (contract-call? .nft-lending-protocol settle-auction auction-id)))
      (asserts! (is-ok settle-result) (err "Failed to settle auction"))
      (print "✓ Auction settled successfully")
      
      ;; 9.3 Verify auction state and NFT ownership
      (print "9.3: Verify auction state and NFT ownership")
      (let ((auction-details (contract-call? .nft-lending-protocol get-auction auction-id)))
        (asserts! (is-ok auction-details) (err "Failed to get auction details"))
        (let ((auction-data (unwrap-panic auction-details)))
          (asserts! (is-eq (get state auction-data) u2) 
                    (err "Auction state is not settled"))
          (print "✓ Auction state verified as settled")
          
          ;; 9.4 Verify NFT ownership transferred to winning bidder
          (print "9.4: Verify NFT ownership transferred")
          (let ((nft-owner (contract-call? .nft-lending-protocol get-nft-owner
                          "test-collection-1" u2)))
            (asserts! (is-ok nft-owner) (err "Failed to get NFT owner"))
            (asserts! (is-eq (unwrap-panic nft-owner) test-address-2) 
                      (err "NFT ownership not transferred to winning bidder"))
            (print "✓ NFT successfully transferred to winning bidder")
          )
        )
      )
    )
  )
)

;; Test 10: Emergency shutdown
(print "Test 10: Test emergency shutdown")
;; 10.1 Activate emergency shutdown
(print "10.1: Activate emergency shutdown")
(let ((result (contract-call? .nft-lending-protocol set-emergency-shutdown true)))
  (asserts! (is-ok result) (err "Failed to activate emergency shutdown"))
  (print "✓ Emergency shutdown activated successfully")
  
  ;; 10.2 Verify operations are restricted
  (print "10.2: Verify operations are restricted")
  (let ((loan-result (contract-call? .nft-lending-protocol apply-for-loan
                     "test-collection-1"
                     u3
                     u5000000
                     u1440)))
    (asserts! (is-err loan-result) (err "Loan application should be restricted"))
    (print "✓ Operations restricted successfully")
    
    ;; 10.3 Deactivate emergency shutdown
    (print "10.3: Deactivate emergency shutdown")
    (let ((deactivate-result (contract-call? .nft-lending-protocol set-emergency-shutdown false)))
      (asserts! (is-ok deactivate-result) (err "Failed to deactivate emergency shutdown"))
      (print "✓ Emergency shutdown deactivated successfully")
      
      ;; 10.4 Verify operations are restored
      (print "10.4: Verify operations are restored")
      (let ((loan-result (contract-call? .nft-lending-protocol apply-for-loan
                         "test-collection-1"
                         u3
                         u5000000
                         u1440)))
        (asserts! (is-ok loan-result) (err "Loan application should be allowed again"))
        (print "✓ Operations restored successfully")
      )
    )
  )
)

;; Final test summary
(print "==========================================")
(print "All tests completed successfully!")
(print "Test coverage:")
(print "- Collection registration")
(print "- Appraiser authorization")
(print "- Appraisal workflow")
(print "- Loan creation")
(print "- Loan repayment (partial and full)")
(print "- Liquidation process")
(print "- Auction bidding and settlement")
(print "- Emergency shutdown functionality")
(print "==========================================")