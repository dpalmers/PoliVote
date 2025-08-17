 
;; PoliVote Petition Management Contract
;; Clarity v2
;; Implements creation, signing, and management of petitions with threshold-based success triggers
;; Integrates with Citizen Token for verified signers to prevent sybil attacks

(define-constant ERR-NOT-AUTHORIZED u100)
(define-constant ERR-PETITION-NOT-FOUND u101)
(define-constant ERR-ALREADY-SIGNED u102)
(define-constant ERR-NOT-SIGNED u103)
(define-constant ERR-PETITION-CLOSED u104)
(define-constant ERR-INSUFFICIENT-THRESHOLD u105)
(define-constant ERR-INVALID-DURATION u106)
(define-constant ERR-INVALID-THRESHOLD u107)
(define-constant ERR-PAUSED u108)
(define-constant ERR-ZERO-ADDRESS u109)
(define-constant ERR-PETITION-EXPIRED u110)
(define-constant ERR-NOT-VERIFIED-CITIZEN u111)
(define-constant ERR-MAX-PETITIONS-REACHED u112)

;; Contract metadata
(define-constant CONTRACT-NAME "PoliVote Petition Management")
(define-constant MAX-PETITIONS u10000) ;; Arbitrary max to prevent spam
(define-constant MIN_THRESHOLD u10) ;; Minimum signatures required
(define-constant MIN_DURATION u144) ;; Minimum 1 day in blocks (~10min/block)
(define-constant MAX_DURATION u52560) ;; Max ~1 year in blocks

;; Admin and state
(define-data-var admin principal tx-sender)
(define-data-var paused bool false)
(define-data-var petition-counter uint u0)

;; Assume Citizen Token contract principal (to be set)
(define-data-var citizen-token-contract principal 'SP000000000000000000002Q6VF78) ;; Placeholder

;; Petition struct
(define-map petitions uint
  {
    creator: principal,
    title: (string-ascii 100),
    description: (string-utf8 500),
    threshold: uint,
    start-block: uint,
    end-block: uint,
    signature-count: uint,
    status: (string-ascii 20) ;; "active", "successful", "expired", "closed"
  }
)

;; Signatures: map petition-id to map signer to bool
(define-map signatures uint (map principal bool))

;; Events (for off-chain indexing)
(define-private (emit-event (event-name (string-ascii 50)) (data (optional (tuple))))
  (print { event: event-name, data: data })
)

;; Private: is-admin
(define-private (is-admin)
  (is-eq tx-sender (var-get admin))
)

;; Private: ensure not paused
(define-private (ensure-not-paused)
  (asserts! (not (var-get paused)) (err ERR-PAUSED))
)

;; Private: check if caller is verified citizen
(define-private (is-verified-citizen (account principal))
  ;; Placeholder: assumes call to citizen token contract's get-balance
  ;; In real: (unwrap-panic (contract-call? (var-get citizen-token-contract) get-balance account)) > u0
  (ok true)
)

;; Transfer admin
(define-public (transfer-admin (new-admin principal))
  (begin
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    (asserts! (not (is-eq new-admin 'SP000000000000000000002Q6VF78)) (err ERR-ZERO-ADDRESS))
    (var-set admin new-admin)
    (ok true)
  )
)

;; Set paused
(define-public (set-paused (pause bool))
  (begin
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    (var-set paused pause)
    (ok pause)
  )
)

;; Set citizen token contract
(define-public (set-citizen-token-contract (contract principal))
  (begin
    (asserts! (is-admin) (err ERR-NOT-AUTHORIZED))
    (var-set citizen-token-contract contract)
    (ok true)
  )
)

;; Create new petition
(define-public (create-petition (title (string-ascii 100)) (description (string-utf8 500)) (threshold uint) (duration uint))
  (begin
    (ensure-not-paused)
    (unwrap! (is-verified-citizen tx-sender) (err ERR-NOT-VERIFIED-CITIZEN))
    (asserts! (>= threshold MIN_THRESHOLD) (err ERR-INVALID-THRESHOLD))
    (asserts! (and (>= duration MIN_DURATION) (<= duration MAX_DURATION)) (err ERR-INVALID-DURATION))
    (let ((petition-id (+ (var-get petition-counter) u1)))
      (asserts! (<= petition-id MAX-PETITIONS) (err ERR-MAX-PETITIONS-REACHED))
      (map-set petitions petition-id
        {
          creator: tx-sender,
          title: title,
          description: description,
          threshold: threshold,
          start-block: block-height,
          end-block: (+ block-height duration),
          signature-count: u0,
          status: "active"
        }
      )
      (var-set petition-counter petition-id)
      (emit-event "petition-created" (some { id: petition-id, creator: tx-sender, threshold: threshold }))
      (ok petition-id)
    )
  )
)

;; Sign a petition
(define-public (sign-petition (petition-id uint))
  (begin
    (ensure-not-paused)
    (unwrap! (is-verified-citizen tx-sender) (err ERR-NOT-VERIFIED-CITIZEN))
    (let ((petition (unwrap! (map-get? petitions petition-id) (err ERR-PETITION-NOT-FOUND))))
      (asserts! (is-eq (get status petition) "active") (err ERR-PETITION-CLOSED))
      (asserts! (<= block-height (get end-block petition)) (err ERR-PETITION-EXPIRED))
      (let ((sig-map (default-to (map principal bool) (map-get? signatures petition-id))))
        (asserts! (not (default-to false (map-get? sig-map tx-sender))) (err ERR-ALREADY-SIGNED))
        (map-set sig-map tx-sender true)
        (map-set signatures petition-id sig-map)
        (let ((new-count (+ (get signature-count petition) u1)))
          (map-set petitions petition-id (merge petition { signature-count: new-count }))
          (if (>= new-count (get threshold petition))
            (begin
              (map-set petitions petition-id (merge petition { status: "successful" }))
              (emit-event "petition-successful" (some { id: petition-id, signatures: new-count }))
            )
            true
          )
          (emit-event "petition-signed" (some { id: petition-id, signer: tx-sender }))
          (ok true)
        )
      )
    )
  )
)

;; Withdraw signature
(define-public (withdraw-signature (petition-id uint))
  (begin
    (ensure-not-paused)
    (let ((petition (unwrap! (map-get? petitions petition-id) (err ERR-PETITION-NOT-FOUND))))
      (asserts! (is-eq (get status petition) "active") (err ERR-PETITION-CLOSED))
      (asserts! (<= block-height (get end-block petition)) (err ERR-PETITION-EXPIRED))
      (let ((sig-map (default-to (map principal bool) (map-get? signatures petition-id))))
        (asserts! (default-to false (map-get? sig-map tx-sender)) (err ERR-NOT-SIGNED))
        (map-delete sig-map tx-sender)
        (map-set signatures petition-id sig-map)
        (map-set petitions petition-id (merge petition { signature-count: (- (get signature-count petition) u1) }))
        (emit-event "signature-withdrawn" (some { id: petition-id, signer: tx-sender }))
        (ok true)
      )
    )
  )
)

;; Close petition
(define-public (close-petition (petition-id uint))
  (begin
    (ensure-not-paused)
    (let ((petition (unwrap! (map-get? petitions petition-id) (err ERR-PETITION-NOT-FOUND))))
      (asserts! (or (is-admin) (is-eq tx-sender (get creator petition))) (err ERR-NOT-AUTHORIZED))
      (asserts! (is-eq (get status petition) "active") (err ERR-PETITION-CLOSED))
      (if (> block-height (get end-block petition))
        (map-set petitions petition-id (merge petition { status: "expired" }))
        (map-set petitions petition-id (merge petition { status: "closed" }))
      )
      (emit-event "petition-closed" (some { id: petition-id, status: (get status petition) }))
      (ok true)
    )
  )
)

;; Read-only: get petition info
(define-read-only (get-petition (id uint))
  (map-get? petitions id)
)

;; Read-only: get signature count
(define-read-only (get-signature-count (id uint))
  (ok (get signature-count (default-to { signature-count: u0 } (map-get? petitions id))))
)

;; Read-only: has signed
(define-read-only (has-signed (id uint) (account principal))
  (let ((sig-map (default-to (map principal bool) (map-get? signatures id))))
    (ok (default-to false (map-get? sig-map account)))
  )
)

;; Read-only: get total petitions
(define-read-only (get-petition-counter)
  (ok (var-get petition-counter))
)

;; Read-only: get admin
(define-read-only (get-admin)
  (ok (var-get admin))
)

;; Read-only: is paused
(define-read-only (is-paused)
  (ok (var-get paused))
)

;; Read-only: get citizen token contract
(define-read-only (get-citizen-token-contract)
  (ok (var-get citizen-token-contract))
)