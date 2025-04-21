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