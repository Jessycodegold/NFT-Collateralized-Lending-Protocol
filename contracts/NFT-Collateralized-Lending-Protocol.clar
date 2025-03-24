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

l,
    collection-id: (string-ascii 32),
    token-id: uint,
    loan-amount: uint,
    interest-rate: uint, ;; Annual rate in basis points
    origination-fee: uint,
    start-block: uint,
    duration: uint, ;; In blocks
    end-block: uint,
    collateral-value: uint,
    loan-to-value: uint, ;; In basis points
    state: uint, ;; 0=Active, 1=Repaid, 2=Defaulted, 3=Liquidated, 4=Expired
    repaid-amount: uint,
    remaining-amount: uint,
    liquidation-trigger: uint, ;; LTV threshold for liquidation in basis points
    last-interest-accrual: uint,
    lenders: (list 10 { lender: principal, amount: uint, share: uint })
  }
)

;; NFT collateral locked in the protocol
(define-map locked-collateral
  { loan-id: uint }
  {
    collection-id: (string-ascii 32),
    token-id: uint,
    owner: principal
  }
)

;; Borrower history for risk assessment
(define-map borrower-history
  { borrower: principal }
  {
    total-loans: uint,
    active-loans: uint,
    repaid-loans: uint,
    defaulted-loans: uint,
    total-borrowed: uint,
    current-debt: uint,
    first-loan-date: uint,
    last-activity: uint,
    risk-score: uint ;; 0-100, higher is riskier
  }
)

;; Liquidation Auctions
(define-map auctions
  { auction-id: uint }
  {
    loan-id: uint,
    collection-id: (string-ascii 32),
    token-id: uint,
    starting-price: uint,
    reserve-price: uint,
    current-bid: uint,
    current-bidder: (optional principal),
    start-block: uint,
    end-block: uint,
    state: uint, ;; 0=Active, 1=Ended, 2=Settled
    original-owner: principal,
    debt-amount: uint,
    bids: (list 20 { bidder: principal, amount: uint, timestamp: uint })
  }
)

;; Authorized Appraisers (Oracles)
(define-map authorized-appraisers
  { appraiser: principal }
  {
    authorized: bool,
    appraisal-count: uint,
    collections: (list 20 (string-ascii 32)),
    accuracy-score: uint, ;; 0-100, higher is better
    last-active: uint
  }
)

;; Appraisal history
(define-map appraisal-requests
  { request-id: uint }
  {
    collection-id: (string-ascii 32),
    token-id: uint,
    requestor: principal,
    timestamp: uint,
    status: (string-ascii 10), ;; "pending", "completed", "rejected"
    appraisals: (list 10 { appraiser: principal, value: uint, timestamp: uint }),
    final-value: (optional uint)
  }
)
(define-data-var next-appraisal-id uint u1)

;; Initialize the protocol
(define-public (initialize (treasury principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set treasury-address treasury)
    (var-set protocol-fee-percentage u200) ;; 2%
    (var-set liquidation-threshold u8000) ;; 80%
    (var-set min-loan-duration u144) ;; 1 day
    (var-set max-loan-duration u52560) ;; 365 days
    (var-set auction-duration u576) ;; 4 days
    (var-set grace-period u144) ;; 1 day
    
    ;; Mint initial supply of lending tokens
    (try! (ft-mint? lending-token u1000000000000 treasury))
    
    (ok true)
  )
)

;; Register a new NFT collection
(define-public (register-collection
  (collection-id (string-ascii 32))
  (nft-contract principal)
  (base-uri (string-utf8 256))
  (max-ltv uint)
  (min-interest-rate uint)
  (max-interest-rate uint)
  (interest-rate-model (string-ascii 10))
  (rarity-levels (list 10 (string-ascii 20)))
  (min-value uint)
  (max-value uint))
  
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-none (map-get? collections { collection-id: collection-id })) err-collection-exists)
    (asserts! (<= max-ltv u7500) err-invalid-parameter) ;; Max 75% LTV
    (asserts! (< min-interest-rate max-interest-rate) err-invalid-parameter)
    (asserts! (<= max-interest-rate u10000) err-invalid-parameter) ;; Max 100% interest
    
    (map-set collections
      { collection-id: collection-id }
      {
        contract: nft-contract,
        base-uri: base-uri,
        max-ltv: max-ltv,
        min-interest-rate: min-interest-rate,
        max-interest-rate: max-interest-rate,
        interest-rate-model: interest-rate-model,
        rarity-levels: rarity-levels,
        min-value: min-value,
        max-value: max-value,
        enabled: true
      }
    )
    
    (ok true)
  )
)

;; Authorize an appraiser/oracle
(define-public (authorize-appraiser (appraiser principal) (collections-list (list 20 (string-ascii 32))))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set authorized-appraisers
      { appraiser: appraiser }
      {
        authorized: true,
        appraisal-count: u0,
        collections: collections-list,
        accuracy-score: u70, ;; Start with a neutral score
        last-active: block-height
      }
    )
    
    (ok true)
  )
)

;; Request an appraisal for an NFT
(define-public (request-appraisal (collection-id (string-ascii 32)) (token-id uint))
  (let (
    (request-id (var-get next-appraisal-id))
    (collection (unwrap! (map-get? collections { collection-id: collection-id }) err-collection-not-found))
  )
    ;; Check that collection is enabled
    (asserts! (get enabled collection) err-collection-not-found)
    
    ;; Create the appraisal request
    (map-set appraisal-requests
      { request-id: request-id }
      {
        collection-id: collection-id,
        token-id: token-id,
        requestor: tx-sender,
        timestamp: block-height,
        status: "pending",
        appraisals: (list),
        final-value: none
      }
    )
    
    ;; Increment the request ID
    (var-set next-appraisal-id (+ request-id u1))
    
    (ok request-id)
  )
)

;; Submit an appraisal (as an oracle)
(define-public (submit-appraisal (request-id uint) (value uint))
  (let (
    (appraiser tx-sender)
    (appraiser-info (unwrap! (map-get? authorized-appraisers { appraiser: appraiser }) err-not-authorized))
    (request (unwrap! (map-get? appraisal-requests { request-id: request-id }) err-asset-not-found))
    (collection-id (get collection-id request))
  )
    ;; Verify the appraiser is authorized
    (asserts! (get authorized appraiser-info) err-not-authorized)
    
    ;; Verify appraiser is authorized for this collection
    (asserts! (is-some (index-of (get collections appraiser-info) collection-id)) err-not-authorized)
    
    ;; Get collection info for validation
    (let (
      (collection (unwrap! (map-get? collections { collection-id: collection-id }) err-collection-not-found))
      (min-value (get min-value collection))
      (max-value (get max-value collection))
    )
      ;; Validate value is within reasonable range
      (asserts! (and (>= value min-value) (<= value max-value)) err-invalid-appraisal)
      
      ;; Add appraisal to the request
      (let (
        (current-appraisals (get appraisals request))
        (updated-appraisals (append current-appraisals {
                               appraiser: appraiser,
                               value: value,
                               timestamp: block-height
                             }))
      )
        (map-set appraisal-requests
          { request-id: request-id }
          (merge request {
            appraisals: updated-appraisals
          })
        )
        
        ;; Update appraiser stats
        (map-set authorized-appraisers
          { appraiser: appraiser }
          (merge appraiser-info {
            appraisal-count: (+ (get appraisal-count appraiser-info) u1),
            last-active: block-height
          })
        )
        
        ;; Check if we have enough appraisals to finalize
        (if (>= (len updated-appraisals) (var-get oracle-consensus-threshold))
          (finalize-appraisal request-id)
          (ok { status: "pending", appraisals: (len updated-appraisals) })
        )
      )
    )
  )
)