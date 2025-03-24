;; NFT-Collateralized Lending Protocol
;; A lending protocol that accepts NFTs as collateral with dynamic valuation

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-collection-exists (err u102))
(define-constant err-collection-not-found (err u103))
(define-constant err-asset-not-found (err u104))
(define-constant err-insufficient-collateral (err u105))
(define-constant err-loan-not-found (err u106))
(define-constant err-loan-already-exists (err u107))
(define-constant err-invalid-loan-state (err u108))
(define-constant err-insufficient-funds (err u109))
(define-constant err-loan-not-liquidatable (err u110))
(define-constant err-loan-not-expired (err u111))
(define-constant err-loan-expired (err u112))
(define-constant err-invalid-appraisal (err u113))
(define-constant err-not-nft-owner (err u114))
(define-constant err-not-nft-approved (err u115))
(define-constant err-bid-too-low (err u116))
(define-constant err-auction-not-found (err u117))
(define-constant err-auction-ended (err u118))
(define-constant err-auction-not-ended (err u119))
(define-constant err-invalid-auction-state (err u120))
(define-constant err-bid-below-reserve (err u121))
(define-constant err-invalid-parameter (err u122))

;; Protocol tokens
(define-fungible-token lending-token)

;; Loan state enumeration
(define-data-var loan-states (list 5 (string-ascii 20)) (list "Active" "Repaid" "Defaulted" "Liquidated" "Expired"))

;; Auction state enumeration
(define-data-var auction-states (list 3 (string-ascii 20)) (list "Active" "Ended" "Settled"))

;; Protocol parameters
(define-data-var next-loan-id uint u1)
(define-data-var next-auction-id uint u1)
(define-data-var protocol-fee-percentage uint u200) ;; 2% in basis points
(define-data-var liquidation-threshold uint u8000) ;; 80% in basis points
(define-data-var min-loan-duration uint u144) ;; 1 day at 144 blocks/day
(define-data-var max-loan-duration uint u52560) ;; 365 days at 144 blocks/day
(define-data-var auction-duration uint u576) ;; 4 days at 144 blocks/day
(define-data-var grace-period uint u144) ;; 1 day grace period after loan expiration
(define-data-var oracle-consensus-threshold uint u3) ;; Need 3 oracles to agree
(define-data-var treasury-address principal contract-owner)
(define-data-var emergency-shutdown bool false)

;; NFT Collection Registry
(define-map collections
  { collection-id: (string-ascii 32) }
  {
    contract: principal,
    base-uri: (string-utf8 256),
    max-ltv: uint, ;; Max loan-to-value ratio in basis points (e.g., 5000 = 50%)
    min-interest-rate: uint, ;; Min annual interest rate in basis points
    max-interest-rate: uint, ;; Max annual interest rate in basis points
    interest-rate-model: (string-ascii 10), ;; "linear", "exponential", etc.
    rarity-levels: (list 10 (string-ascii 20)), ;; "Common", "Uncommon", "Rare", etc.
    min-value: uint, ;; Minimum value for any NFT in the collection
    max-value: uint, ;; Maximum value for any NFT in the collection
    enabled: bool
  }
)

;; Registered NFT Assets with latest appraisals
(define-map nft-assets
  { collection-id: (string-ascii 32), token-id: uint }
  {
    current-appraisal: uint,
    rarity-score: uint, ;; 0-100 score
    rarity-rank: uint,  ;; 1 = most rare
    traits: (list 20 { trait-type: (string-ascii 32), value: (string-utf8 64) }),
    last-appraisal-date: uint,
    appraisal-count: uint,
    appraisal-history: (list 10 { value: uint, timestamp: uint, appraiser: principal }),
    collection-id: (string-ascii 32)
  }
)