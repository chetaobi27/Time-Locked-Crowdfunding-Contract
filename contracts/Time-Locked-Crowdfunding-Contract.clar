(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-CAMPAIGN-ENDED (err u102))
(define-constant ERR-CAMPAIGN-NOT-ENDED (err u103))
(define-constant ERR-GOAL-NOT-MET (err u104))
(define-constant ERR-NO-CONTRIBUTION (err u105))
(define-constant ERR-ALREADY-CLAIMED (err u106))
(define-constant ERR-MILESTONE-NOT-FOUND (err u107))

(define-data-var campaign-owner principal tx-sender)
(define-data-var campaign-goal uint u0)
(define-data-var campaign-deadline uint u0)
(define-data-var total-raised uint u0)
(define-data-var is-active bool true)

(define-map contributions 
    principal 
    {amount: uint, claimed: bool})

(define-map milestones 
    uint 
    {amount: uint, deadline: uint, released: bool})

(define-public (initialize (goal uint) (duration uint))
    (begin
        (asserts! (is-eq tx-sender (var-get campaign-owner)) ERR-UNAUTHORIZED)
        (var-set campaign-goal goal)
        (var-set campaign-deadline (+ stacks-block-height duration))
        (ok true)))

(define-public (add-milestone (milestone-id uint) (amount uint) (deadline uint))
    (begin
        (asserts! (is-eq tx-sender (var-get campaign-owner)) ERR-UNAUTHORIZED)
        (map-set milestones milestone-id {
            amount: amount,
            deadline: deadline,
            released: false
        })
        (ok true)))

(define-public (contribute)
    (let ((current-contribution (default-to {amount: u0, claimed: false} 
            (map-get? contributions tx-sender))))
        (begin
            (asserts! (< stacks-block-height (var-get campaign-deadline)) ERR-CAMPAIGN-ENDED)
            (asserts! (> (stx-get-balance tx-sender) u0) ERR-INVALID-AMOUNT)
            (map-set contributions tx-sender 
                {amount: (+ (get amount current-contribution) (stx-get-balance tx-sender)),
                 claimed: false})
            (var-set total-raised (+ (var-get total-raised) (stx-get-balance tx-sender)))
            (ok true))))

(define-public (release-milestone (milestone-id uint))
    (let ((milestone (unwrap! (map-get? milestones milestone-id) ERR-MILESTONE-NOT-FOUND)))
        (begin
            (asserts! (is-eq tx-sender (var-get campaign-owner)) ERR-UNAUTHORIZED)
            (asserts! (>= stacks-block-height (get deadline milestone)) ERR-CAMPAIGN-NOT-ENDED)
            (asserts! (>= (var-get total-raised) (var-get campaign-goal)) ERR-GOAL-NOT-MET)
            (asserts! (not (get released milestone)) ERR-ALREADY-CLAIMED)
            (map-set milestones milestone-id 
                (merge milestone {released: true}))
            (try! (as-contract
                (stx-transfer? 
                    (get amount milestone)
                    tx-sender
                    (var-get campaign-owner))))
            (ok true))))
(define-public (claim-refund)
    (let ((contribution (unwrap! (map-get? contributions tx-sender) ERR-NO-CONTRIBUTION)))
        (begin
            (asserts! (>= stacks-block-height (var-get campaign-deadline)) ERR-CAMPAIGN-NOT-ENDED)
            (asserts! (< (var-get total-raised) (var-get campaign-goal)) ERR-GOAL-NOT-MET)
            (asserts! (not (get claimed contribution)) ERR-ALREADY-CLAIMED)
            (map-set contributions tx-sender 
                (merge contribution {claimed: true}))
            (try! (as-contract
                (stx-transfer? 
                    (get amount contribution)
                    tx-sender
                    tx-sender)))
            (ok true))))
(define-read-only (get-campaign-details)
    (ok {
        owner: (var-get campaign-owner),
        goal: (var-get campaign-goal),
        deadline: (var-get campaign-deadline),
        total-raised: (var-get total-raised),
        is-active: (var-get is-active)
    }))

(define-read-only (get-contribution (contributor principal))
    (ok (map-get? contributions contributor)))

(define-read-only (get-milestone (milestone-id uint))
    (ok (map-get? milestones milestone-id)))

(define-constant ERR-EXTENSION-NOT-ALLOWED (err u200))
(define-constant ERR-ALREADY-VOTED (err u201))
(define-constant ERR-EXTENSION-ACTIVE (err u202))
(define-constant ERR-INSUFFICIENT-PROGRESS (err u203))

(define-data-var extension-proposal-active bool false)
(define-data-var extension-proposal-deadline uint u0)
(define-data-var extension-duration uint u0)
(define-data-var extension-votes-for uint u0)
(define-data-var extension-votes-against uint u0)
(define-data-var extension-total-voting-power uint u0)

(define-map extension-voters principal bool)

(define-public (propose-extension (duration uint))
    (let ((progress-percentage (/ (* (var-get total-raised) u100) (var-get campaign-goal))))
        (begin
            (asserts! (not (var-get extension-proposal-active)) ERR-EXTENSION-ACTIVE)
            (asserts! (>= progress-percentage u75) ERR-INSUFFICIENT-PROGRESS)
            (asserts! (< (- (var-get campaign-deadline) stacks-block-height) u144) ERR-EXTENSION-NOT-ALLOWED)
            (var-set extension-proposal-active true)
            (var-set extension-proposal-deadline (+ stacks-block-height u144))
            (var-set extension-duration duration)
            (var-set extension-votes-for u0)
            (var-set extension-votes-against u0)
            (var-set extension-total-voting-power (var-get total-raised))
            (ok true))))

(define-public (vote-extension (support bool))
    (let ((contribution (unwrap! (map-get? contributions tx-sender) ERR-NO-CONTRIBUTION)))
        (begin
            (asserts! (var-get extension-proposal-active) ERR-EXTENSION-NOT-ALLOWED)
            (asserts! (< stacks-block-height (var-get extension-proposal-deadline)) ERR-CAMPAIGN-ENDED)
            (asserts! (is-none (map-get? extension-voters tx-sender)) ERR-ALREADY-VOTED)
            (map-set extension-voters tx-sender true)
            (if support
                (var-set extension-votes-for (+ (var-get extension-votes-for) (get amount contribution)))
                (var-set extension-votes-against (+ (var-get extension-votes-against) (get amount contribution))))
            (ok true))))

(define-public (execute-extension)
    (let ((votes-for (var-get extension-votes-for))
          (votes-against (var-get extension-votes-against))
          (total-votes (+ votes-for votes-against))
          (voting-power (var-get extension-total-voting-power)))
        (begin
            (asserts! (var-get extension-proposal-active) ERR-EXTENSION-NOT-ALLOWED)
            (asserts! (>= stacks-block-height (var-get extension-proposal-deadline)) ERR-CAMPAIGN-NOT-ENDED)
            (asserts! (>= total-votes (/ voting-power u2)) ERR-INSUFFICIENT-PROGRESS)
            (asserts! (> votes-for votes-against) ERR-GOAL-NOT-MET)
            (var-set campaign-deadline (+ (var-get campaign-deadline) (var-get extension-duration)))
            (var-set extension-proposal-active false)
            (ok true))))

(define-read-only (get-extension-status)
    (ok {
        active: (var-get extension-proposal-active),
        deadline: (var-get extension-proposal-deadline),
        duration: (var-get extension-duration),
        votes-for: (var-get extension-votes-for),
        votes-against: (var-get extension-votes-against),
        total-voting-power: (var-get extension-total-voting-power)
    }))

    (define-constant ERR-BATCH-SIZE-EXCEEDED (err u300))
(define-constant ERR-REFUND-NOT-AVAILABLE (err u301))
(define-constant ERR-BATCH-EMPTY (err u302))

(define-data-var max-batch-size uint u50)
(define-data-var auto-refund-enabled bool false)
(define-data-var refund-processing-active bool false)

(define-map refund-queue principal uint)
(define-data-var queue-length uint u0)

(define-public (enable-auto-refund)
    (begin
        (asserts! (is-eq tx-sender (var-get campaign-owner)) ERR-UNAUTHORIZED)
        (asserts! (>= stacks-block-height (var-get campaign-deadline)) ERR-CAMPAIGN-NOT-ENDED)
        (asserts! (< (var-get total-raised) (var-get campaign-goal)) ERR-GOAL-NOT-MET)
        (var-set auto-refund-enabled true)
        (ok true)))

(define-public (queue-for-refund)
    (let ((contribution (unwrap! (map-get? contributions tx-sender) ERR-NO-CONTRIBUTION)))
        (begin
            (asserts! (var-get auto-refund-enabled) ERR-REFUND-NOT-AVAILABLE)
            (asserts! (not (get claimed contribution)) ERR-ALREADY-CLAIMED)
            (asserts! (is-none (map-get? refund-queue tx-sender)) ERR-ALREADY-CLAIMED)
            (map-set refund-queue tx-sender (get amount contribution))
            (var-set queue-length (+ (var-get queue-length) u1))
            (ok true))))

(define-public (process-batch-refunds (recipients (list 50 principal)))
    (begin
        (asserts! (var-get auto-refund-enabled) ERR-REFUND-NOT-AVAILABLE)
        (asserts! (not (var-get refund-processing-active)) ERR-REFUND-NOT-AVAILABLE)
        (asserts! (> (len recipients) u0) ERR-BATCH-EMPTY)
        (asserts! (<= (len recipients) (var-get max-batch-size)) ERR-BATCH-SIZE-EXCEEDED)
        (var-set refund-processing-active true)
        (try! (fold process-single-refund recipients (ok true)))
        (var-set refund-processing-active false)
        (ok true)))

(define-private (process-single-refund (recipient principal) (previous-result (response bool uint)))
    (match previous-result
        success (let ((refund-amount (default-to u0 (map-get? refund-queue recipient)))
                     (contribution (default-to {amount: u0, claimed: false} (map-get? contributions recipient))))
            (if (and (> refund-amount u0) (not (get claimed contribution)))
                (begin
                    (map-delete refund-queue recipient)
                    (map-set contributions recipient (merge contribution {claimed: true}))
                    (var-set queue-length (- (var-get queue-length) u1))
                    (match (as-contract (stx-transfer? refund-amount tx-sender recipient))
                        transfer-success (ok true)
                        transfer-error (err transfer-error)))
                (ok true)))
        error (err error)))

(define-public (emergency-refund-all)
    (begin
        (asserts! (is-eq tx-sender (var-get campaign-owner)) ERR-UNAUTHORIZED)
        (asserts! (>= stacks-block-height (var-get campaign-deadline)) ERR-CAMPAIGN-NOT-ENDED)
        (var-set auto-refund-enabled true)
        (var-set is-active false)
        (ok true)))

(define-read-only (get-refund-status)
    (ok {
        auto-refund-enabled: (var-get auto-refund-enabled),
        processing-active: (var-get refund-processing-active),
        queue-length: (var-get queue-length),
        max-batch-size: (var-get max-batch-size)
    }))

(define-read-only (get-user-refund-status (user principal))
    (ok {
        queued-amount: (default-to u0 (map-get? refund-queue user)),
        in-queue: (is-some (map-get? refund-queue user))
    }))

(define-constant ERR-REWARD-NOT-FOUND (err u400))
(define-constant ERR-REWARD-CLAIMED (err u401))
(define-constant ERR-INELIGIBLE-REWARD (err u402))
(define-constant ERR-REWARD-EXISTS (err u403))

(define-map reward-tiers 
    uint 
    {min-contribution: uint, reward-description: (string-ascii 100), max-claims: uint, claimed: uint})

(define-map user-rewards 
    {user: principal, tier-id: uint}
    {claimed: bool, claim-timestamp: uint})

(define-data-var next-tier-id uint u1)

(define-public (create-reward-tier (min-contribution uint) (reward-description (string-ascii 100)) (max-claims uint))
    (let ((tier-id (var-get next-tier-id)))
        (begin
            (asserts! (is-eq tx-sender (var-get campaign-owner)) ERR-UNAUTHORIZED)
            (map-set reward-tiers tier-id {
                min-contribution: min-contribution,
                reward-description: reward-description,
                max-claims: max-claims,
                claimed: u0
            })
            (var-set next-tier-id (+ tier-id u1))
            (ok tier-id))))

(define-public (claim-reward (tier-id uint))
    (let ((tier (unwrap! (map-get? reward-tiers tier-id) ERR-REWARD-NOT-FOUND))
          (contribution (unwrap! (map-get? contributions tx-sender) ERR-NO-CONTRIBUTION))
          (user-reward-key {user: tx-sender, tier-id: tier-id})
          (existing-claim (map-get? user-rewards user-reward-key)))
        (begin
            (asserts! (>= stacks-block-height (var-get campaign-deadline)) ERR-CAMPAIGN-NOT-ENDED)
            (asserts! (>= (var-get total-raised) (var-get campaign-goal)) ERR-GOAL-NOT-MET)
            (asserts! (>= (get amount contribution) (get min-contribution tier)) ERR-INELIGIBLE-REWARD)
            (asserts! (< (get claimed tier) (get max-claims tier)) ERR-REWARD-CLAIMED)
            (asserts! (is-none existing-claim) ERR-REWARD-CLAIMED)
            (map-set user-rewards user-reward-key {
                claimed: true,
                claim-timestamp: stacks-block-height
            })
            (map-set reward-tiers tier-id 
                (merge tier {claimed: (+ (get claimed tier) u1)}))
            (ok true))))

(define-read-only (get-reward-tier (tier-id uint))
    (ok (map-get? reward-tiers tier-id)))

(define-read-only (get-user-reward-status (user principal) (tier-id uint))
    (ok (map-get? user-rewards {user: user, tier-id: tier-id})))

(define-read-only (get-eligible-rewards (user principal))
    (let ((contribution (map-get? contributions user)))
        (if (is-some contribution)
            (let ((contribution-data (unwrap-panic contribution))
                  (contribution-amount (get amount contribution-data)))
                (ok {
                    contribution-amount: contribution-amount,
                    eligible-tiers: (filter check-tier-eligibility (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10))
                }))
            (ok {contribution-amount: u0, eligible-tiers: (list)}))))

(define-private (check-tier-eligibility (tier-id uint))
    (is-some (map-get? reward-tiers tier-id)))