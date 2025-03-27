;; AutoSaveSTX - A Clarity smart contract for time-locked savings

(define-data-var vault-counter uint u0)  ;; Tracks vault IDs

;; Mapping: vault ID -> savings details
(define-map vaults 
  { id: uint } 
  (tuple (owner principal) (amount uint) (unlock-block uint) (withdrawn bool))
)

;; ------------------- Deposit to Auto-Savings Vault -------------------
(define-public (deposit (amount uint) (lock-period uint))
  (let ((vault-id (+ (var-get vault-counter) u1))
        (unlock-block (+ stacks-block-height lock-period)))
    (begin
      ;; Validate inputs
      (asserts! (> amount u0) (err u1000))  ;; Ensure positive deposit
      (asserts! (> lock-period u0) (err u1001))  ;; Ensure valid lock period
      (asserts! (<= amount (stx-get-balance tx-sender)) (err u1006))  ;; Ensure user has enough balance
      
      ;; Transfer STX to contract
      (match (stx-transfer? amount tx-sender (as-contract tx-sender))
        success
          (begin
            (var-set vault-counter vault-id)
            (map-set vaults { id: vault-id } 
              { owner: tx-sender, amount: amount, unlock-block: unlock-block, withdrawn: false })
            (ok vault-id))
        error (err u1002)
      )
    )
  )
)

;; ------------------- Withdraw from Vault -------------------
(define-public (withdraw (vault-id uint))
  (match (map-get? vaults { id: vault-id })
    vault
      (begin
        ;; Validate withdrawal conditions
        (asserts! (is-eq tx-sender (get owner vault)) (err u1007))  ;; Must be vault owner
        (asserts! (>= stacks-block-height (get unlock-block vault)) (err u1008))  ;; Lock period must be over
        (asserts! (not (get withdrawn vault)) (err u1009))  ;; Must not be already withdrawn
        
        ;; Transfer STX back to owner
        (match (stx-transfer? (get amount vault) (as-contract tx-sender) tx-sender)
          success
            (begin
              (map-set vaults { id: vault-id } (merge vault { withdrawn: true }))
              (ok true))
          error (err u1003)
        )
      )
    (err u1005)  ;; Vault not found
  )
)

;; ------------------- Check Vault Status -------------------
(define-read-only (get-vault (vault-id uint))
  (match (map-get? vaults { id: vault-id })
    vault (ok (some vault))
    (ok none)
  )
)

;; ------------------- Get Time Remaining -------------------
(define-read-only (get-time-remaining (vault-id uint))
  (match (map-get? vaults { id: vault-id })
    vault 
      (let ((unlock-at (get unlock-block vault))
            (current-height stacks-block-height))
        (if (>= current-height unlock-at)
          (ok u0)
          (ok (- unlock-at current-height))))
    (err u1005)  ;; Vault not found
  )
)