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

;; Finalize an appraisal (private helper)
(define-private (finalize-appraisal (request-id uint))
  (let (
    (request (unwrap! (map-get? appraisal-requests { request-id: request-id }) err-asset-not-found))
    (appraisals (get appraisals request))
  )
    ;; Calculate median value from all appraisals
    (let (
      (values-list (map get-value-from-appraisal appraisals))
      (median-value (get-median values-list))
      (collection-id (get collection-id request))
      (token-id (get token-id request))
    )
      ;; Update the request with final value
      (map-set appraisal-requests
        { request-id: request-id }
        (merge request {
          status: "completed",
          final-value: (some median-value)
        })
      )
      
      ;; Update the NFT asset with new appraisal
      (update-asset-appraisal collection-id token-id median-value appraisals)
      
      (ok {
        collection-id: collection-id,
        token-id: token-id,
        value: median-value
      })
    )
  )
)

;; Helper to get value from appraisal
(define-private (get-value-from-appraisal (appraisal { appraiser: principal, value: uint, timestamp: uint }))
  (get value appraisal)
)

;; Calculate median of a list of values
(define-private (get-median (values (list 10 uint)))
  (let (
    (sorted-values (sort values))
    (len (len values))
    (middle (/ len u2))
  )
    (if (is-eq (mod len u2) u0)
      ;; Even number of values, take average of middle two
      (let (
        (val1 (unwrap-panic (element-at sorted-values middle)))
        (val2 (unwrap-panic (element-at sorted-values (- middle u1))))
      )
        (/ (+ val1 val2) u2)
      )
      ;; Odd number of values, take middle one
      (unwrap-panic (element-at sorted-values middle))
    )
  )
)

;; Helper to sort a list of values (simple bubble sort)
(define-private (sort (values (list 10 uint)))
  (fold sorter values values)
)

;; Helper for sorting algorithm
(define-private (sorter (i uint) (values (list 10 uint)))
  (fold (lambda (j acc) (bubble j acc)) values values)
)

;; Bubble sort helper
(define-private (bubble (val1 uint) (values (list 10 uint)))
  (match (bubble-helper val1 values u0 (len values))
    result result
    values
  )
)

;; Bubble sort implementation
(define-private (bubble-helper (val uint) (values (list 10 uint)) (index uint) (len uint))
  (if (>= index (- len u1))
    values
    (let (
      (next-val (default-to u0 (element-at values (+ index u1))))
    )
      (if (> val next-val)
        (bubble-helper val (swap-at values index (+ index u1)) (+ index u1) len)
        (bubble-helper val values (+ index u1) len)
      )
    )
  )
)

;; Helper to swap elements in a list
(define-private (swap-at (values (list 10 uint)) (i uint) (j uint))
  (let (
    (val-i (unwrap-panic (element-at values i)))
    (val-j (unwrap-panic (element-at values j)))
  )
    (replace-at (replace-at values i val-j) j val-i)
  )
)

;; Update NFT asset appraisal data
(define-private (update-asset-appraisal
  (collection-id (string-ascii 32))
  (token-id uint)
  (value uint)
  (appraisals (list 10 { appraiser: principal, value: uint, timestamp: uint })))
  
  (let (
    (asset (map-get? nft-assets { collection-id: collection-id, token-id: token-id }))
    (rarity-score (if (is-some asset) 
                     (get rarity-score (unwrap-panic asset)) 
                     (calculate-rarity-score collection-id token-id)))
    (rarity-rank (if (is-some asset)
                    (get rarity-rank (unwrap-panic asset))
                    u1))
    (traits (if (is-some asset)
               (get traits (unwrap-panic asset))
               (list)))
    (appraisal-count (if (is-some asset)
                        (+ (get appraisal-count (unwrap-panic asset)) u1)
                        u1))
    (appraisal-history (if (is-some asset)
                          (get appraisal-history (unwrap-panic asset))
                          (list)))
    ;; Take the most recent 3 appraisals including this one
    (new-history (take u3 (append appraisal-history {
                           value: value,
                           timestamp: block-height,
                           appraiser: tx-sender
                         })))
  )
    (map-set nft-assets
      { collection-id: collection-id, token-id: token-id }
      {
        current-appraisal: value,
        rarity-score: rarity-score,
        rarity-rank: rarity-rank,
        traits: traits,
        last-appraisal-date: block-height,
        appraisal-count: appraisal-count,
        appraisal-history: new-history,
        collection-id: collection-id
      }
    )
    
    true
  )
)

;; Calculate rarity score for an NFT (simplified version)
(define-private (calculate-rarity-score (collection-id (string-ascii 32)) (token-id uint))
  ;; In a real implementation, this would analyze trait distributions
  ;; For this example, we'll return a fixed score between 30-85
  (let (
    (pseudorandom-source (sha256 (concat (to-consensus-buff collection-id) 
                                        (to-consensus-buff token-id))))
    (first-byte (unwrap-panic (element-at pseudorandom-source u0)))
  )
    (+ u30 (mod first-byte u55))
  )
)

;; Apply for a loan against an NFT
(define-public (apply-for-loan
  (collection-id (string-ascii 32))
  (token-id uint)
  (loan-amount uint)
  (duration uint))
  
  (let (
    (borrower tx-sender)
    (loan-id (var-get next-loan-id))
    (collection (unwrap! (map-get? collections { collection-id: collection-id }) err-collection-not-found))
    (asset (unwrap! (map-get? nft-assets { collection-id: collection-id, token-id: token-id }) err-asset-not-found))
    (nft-contract (get contract collection))
    (nft-value (get current-appraisal asset))
    (max-ltv (get max-ltv collection))
    (requested-ltv (/ (* loan-amount u10000) nft-value))
  )
    ;; Validation checks
    (asserts! (get enabled collection) err-collection-not-found)
    (asserts! (>= nft-value loan-amount) err-insufficient-collateral)
    (asserts! (<= requested-ltv max-ltv) err-insufficient-collateral)
    (asserts! (>= duration (var-get min-loan-duration)) err-invalid-parameter)
    (asserts! (<= duration (var-get max-loan-duration)) err-invalid-parameter)
    
    ;; Verify NFT ownership
    (asserts! (is-owner nft-contract token-id borrower) err-not-nft-owner)
    
    ;; Calculate loan parameters
    (let (
      (ltv requested-ltv)
      (interest-rate (calculate-interest-rate collection asset ltv))
      (origination-fee (/ (* loan-amount (var-get protocol-fee-percentage)) u10000))
      (liquidation-trigger (/ (* (var-get liquidation-threshold) max-ltv) u10000))
    )
      ;; Transfer NFT to contract
      (try! (transfer-nft nft-contract token-id borrower (as-contract tx-sender)))
      
      ;; Create the loan
      (map-set loans
        { loan-id: loan-id }
        {
          borrower: borrower,
          collection-id: collection-id,
          token-id: token-id,
          loan-amount: loan-amount,
          interest-rate: interest-rate,
          origination-fee: origination-fee,
          start-block: block-height,
          duration: duration,
          end-block: (+ block-height duration),
          collateral-value: nft-value,
          loan-to-value: ltv,
          state: u0, ;; Active
          repaid-amount: u0,
          remaining-amount: loan-amount,
          liquidation-trigger: liquidation-trigger,
          last-interest-accrual: block-height,
          lenders: (list)
        }
      )
      
      ;; Record the collateral as locked
      (map-set locked-collateral
        { loan-id: loan-id }
        {
          collection-id: collection-id,
          token-id: token-id,
          owner: borrower
        }
      )
      
      ;; Update borrower history
      (update-borrower-history borrower loan-amount true)
      
      ;; Increment loan ID
      (var-set next-loan-id (+ loan-id u1))
      
      ;; Transfer loan amount to borrower minus fees
      (as-contract (try! (ft-transfer? lending-token (- loan-amount origination-fee) (as-contract tx-sender) borrower)))
      
      ;; Transfer fees to treasury
      (as-contract (try! (ft-transfer? lending-token origination-fee (as-contract tx-sender) (var-get treasury-address))))
      
      (ok loan-id)
    )
  )
)

;; Helper to check NFT ownership
(define-private (is-owner (nft-contract principal) (token-id uint) (owner principal))
  ;; In a real implementation, this would query the NFT contract
  ;; For simplicity, returning true
  true
)

;; Helper to transfer NFT
(define-private (transfer-nft (nft-contract principal) (token-id uint) (sender principal) (recipient principal))
  ;; In a real implementation, this would call the NFT contract's transfer function
  ;; For simplicity, returning ok
  (ok true)
)

;; Calculate interest rate based on collateral quality and LTV
(define-private (calculate-interest-rate
  (collection (tuple contract: principal, base-uri: (string-utf8 256), max-ltv: uint, min-interest-rate: uint, max-interest-rate: uint, interest-rate-model: (string-ascii 10), rarity-levels: (list 10 (string-ascii 20)), min-value: uint, max-value: uint, enabled: bool))
  (asset (tuple current-appraisal: uint, rarity-score: uint, rarity-rank: uint, traits: (list 20 { trait-type: (string-ascii 32), value: (string-utf8 64) }), last-appraisal-date: uint, appraisal-count: uint, appraisal-history: (list 10 { value: uint, timestamp: uint, appraiser: principal }), collection-id: (string-ascii 32)))
  (ltv uint))
  
  (let (
    (min-rate (get min-interest-rate collection))
    (max-rate (get max-interest-rate collection))
    (max-ltv (get max-ltv collection))
    (rarity-score (get rarity-score asset))
    (model (get interest-rate-model collection))
    
    ;; Rarity adjustment factor (higher rarity = lower interest)
    (rarity-factor (/ (* (- u100 rarity-score) u1000) u100))
    
    ;; LTV factor (higher LTV = higher interest)
    (ltv-factor (/ (* ltv u1000) max-ltv))
  )
    (if (is-eq model "linear")
      ;; Linear model: min + (max - min) * ltv/maxLtv - rarityAdjustment
      (let (
        (range (- max-rate min-rate))
        (ltv-component (/ (* range ltv-factor) u1000))
        (rarity-adjustment (/ (* range rarity-factor) u1000))
        (final-rate (+ min-rate ltv-component (- rarity-adjustment)))
      )
        ;; Ensure within bounds
        (if (< final-rate min-rate)
          min-rate
          (if (> final-rate max-rate)
            max-rate
            final-rate
          )
        )
      )
      ;; Default to exponential model
      (let (
        (base-rate min-rate)
        (ltv-exponent (/ ltv u2000)) ;; 0.5 power for exponential curve
        (rarity-discount (/ (* (- max-rate min-rate) rarity-factor) u1000))
        (final-rate (+ base-rate (/ (* (- max-rate min-rate) ltv-exponent) u1) (- rarity-discount)))
      )
        ;; Ensure within bounds
        (if (< final-rate min-rate)
          min-rate
          (if (> final-rate max-rate)
            max-rate
            final-rate
          )
        )
      )
    )
  )
)

;; Update borrower history
(define-private (update-borrower-history (borrower principal) (amount uint) (is-new-loan bool))
  (let (
    (existing (default-to {
                total-loans: u0,
                active-loans: u0,
                repaid-loans: u0,
                defaulted-loans: u0,
                total-borrowed: u0,
                current-debt: u0,
                first-loan-date: block-height,
                last-activity: block-height,
                risk-score: u50
              } (map-get? borrower-history { borrower: borrower })))
  )
    (map-set borrower-history
      { borrower: borrower }
      (merge existing {
        total-loans: (if is-new-loan (+ (get total-loans existing) u1) (get total-loans existing)),
        active-loans: (if is-new-loan (+ (get active-loans existing) u1) (get active-loans existing)),
        total-borrowed: (+ (get total-borrowed existing) amount),
        current-debt: (+ (get current-debt existing) amount),
        last-activity: block-height
      })
    )
  )
)

;; Repay a loan (full or partial)
(define-public (repay-loan (loan-id uint) (amount uint))
  (let (
    (borrower tx-sender)
    (loan (unwrap! (map-get? loans { loan-id: loan-id }) err-loan-not-found))
  )
    ;; Validate loan is active
    (asserts! (is-eq (get state loan) u0) err-invalid-loan-state)
    
    ;; Validate borrower is the loan's borrower
    (asserts! (is-eq borrower (get borrower loan)) err-not-authorized)
     ;; Process accrued interest
    (let (
      (updated-loan (accrue-interest loan-id))
      (remaining (get remaining-amount updated-loan))
      (repay-amount (if (> amount remaining) remaining amount))
    )
      ;; Ensure borrower has enough tokens
      (asserts! (>= (ft-get-balance lending-token borrower) repay-amount) err-insufficient-funds)
      
      ;; Transfer tokens from borrower to contract
      (try! (ft-transfer? lending-token repay-amount borrower (as-contract tx-sender)))