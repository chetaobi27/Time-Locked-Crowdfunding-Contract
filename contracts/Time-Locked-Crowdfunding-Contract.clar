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

(define-constant ERR-MILESTONE-THRESHOLD-NOT-MET (err u500))
(define-constant ERR-RELEASE-AMOUNT-INVALID (err u501))
(define-constant ERR-PROGRESSIVE-RELEASE-NOT-ENABLED (err u502))
(define-constant ERR-INSUFFICIENT_FUNDS (err u503))

(define-data-var progressive-release-enabled bool false)
(define-data-var total-progressive-released uint u0)
(define-data-var progressive-release-percentage uint u20)

(define-map progressive-thresholds
    uint
    {threshold-percentage: uint, release-percentage: uint, unlocked: bool})

(define-data-var next-threshold-id uint u1)

(define-public (enable-progressive-release)
    (begin
        (asserts! (is-eq tx-sender (var-get campaign-owner)) ERR-UNAUTHORIZED)
        (asserts! (< stacks-block-height (var-get campaign-deadline)) ERR-CAMPAIGN-ENDED)
        (var-set progressive-release-enabled true)
        (ok true)))

(define-public (create-progressive-threshold (threshold-percentage uint) (release-percentage uint))
    (let ((threshold-id (var-get next-threshold-id)))
        (begin
            (asserts! (is-eq tx-sender (var-get campaign-owner)) ERR-UNAUTHORIZED)
            (asserts! (<= threshold-percentage u100) ERR-INVALID-AMOUNT)
            (asserts! (<= release-percentage u100) ERR-INVALID-AMOUNT)
            (asserts! (> threshold-percentage u0) ERR-INVALID-AMOUNT)
            (asserts! (> release-percentage u0) ERR-INVALID-AMOUNT)
            (map-set progressive-thresholds threshold-id {
                threshold-percentage: threshold-percentage,
                release-percentage: release-percentage,
                unlocked: false
            })
            (var-set next-threshold-id (+ threshold-id u1))
            (ok threshold-id))))

(define-public (unlock-progressive-funds (threshold-id uint))
    (let ((threshold (unwrap! (map-get? progressive-thresholds threshold-id) ERR-MILESTONE-THRESHOLD-NOT-MET))
          (current-progress (/ (* (var-get total-raised) u100) (var-get campaign-goal)))
          (release-amount (/ (* (var-get total-raised) (get release-percentage threshold)) u100))
          (contract-balance (stx-get-balance (as-contract tx-sender))))
        (begin
            (asserts! (var-get progressive-release-enabled) ERR-PROGRESSIVE-RELEASE-NOT-ENABLED)
            (asserts! (>= current-progress (get threshold-percentage threshold)) ERR-MILESTONE-THRESHOLD-NOT-MET)
            (asserts! (not (get unlocked threshold)) ERR-ALREADY-CLAIMED)
            (asserts! (>= contract-balance release-amount) ERR-INSUFFICIENT_FUNDS)
            (map-set progressive-thresholds threshold-id 
                (merge threshold {unlocked: true}))
            (var-set total-progressive-released 
                (+ (var-get total-progressive-released) release-amount))
            (try! (as-contract
                (stx-transfer? 
                    release-amount
                    tx-sender
                    (var-get campaign-owner))))
            (ok release-amount))))

(define-public (claim-remaining-funds)
    (let ((remaining-amount (- (var-get total-raised) (var-get total-progressive-released)))
          (contract-balance (stx-get-balance (as-contract tx-sender))))
        (begin
            (asserts! (is-eq tx-sender (var-get campaign-owner)) ERR-UNAUTHORIZED)
            (asserts! (>= stacks-block-height (var-get campaign-deadline)) ERR-CAMPAIGN-NOT-ENDED)
            (asserts! (>= (var-get total-raised) (var-get campaign-goal)) ERR-GOAL-NOT-MET)
            (asserts! (> remaining-amount u0) ERR-INVALID-AMOUNT)
            (asserts! (>= contract-balance remaining-amount) ERR-INSUFFICIENT_FUNDS)
            (var-set total-progressive-released (var-get total-raised))
            (try! (as-contract
                (stx-transfer? 
                    remaining-amount
                    tx-sender
                    (var-get campaign-owner))))
            (ok remaining-amount))))

(define-read-only (get-progressive-release-status)
    (ok {
        enabled: (var-get progressive-release-enabled),
        total-released: (var-get total-progressive-released),
        remaining-funds: (- (var-get total-raised) (var-get total-progressive-released)),
        release-percentage: (var-get progressive-release-percentage)
    }))

(define-read-only (get-progressive-threshold (threshold-id uint))
    (ok (map-get? progressive-thresholds threshold-id)))

(define-read-only (check-threshold-eligibility (threshold-id uint))
    (let ((threshold (map-get? progressive-thresholds threshold-id))
          (current-progress (/ (* (var-get total-raised) u100) (var-get campaign-goal))))
        (if (is-some threshold)
            (let ((threshold-data (unwrap-panic threshold)))
                (ok {
                    eligible: (>= current-progress (get threshold-percentage threshold-data)),
                    unlocked: (get unlocked threshold-data),
                    current-progress: current-progress,
                    required-progress: (get threshold-percentage threshold-data)
                }))
            (ok {eligible: false, unlocked: false, current-progress: u0, required-progress: u0}))))

;; ===== CAMPAIGN ANALYTICS & METRICS SYSTEM =====

;; Analytics error constants
(define-constant ERR-ANALYTICS-DISABLED (err u600))
(define-constant ERR-INVALID-TIMEFRAME (err u601))
(define-constant ERR-SNAPSHOT-EXISTS (err u602))
(define-constant ERR-NO-ANALYTICS-DATA (err u603))

;; Analytics data variables
(define-data-var analytics-enabled bool true)
(define-data-var total-contributors uint u0)
(define-data-var highest-contribution uint u0)
(define-data-var lowest-contribution uint u1000000000000)
(define-data-var campaign-creation-block uint u0)
(define-data-var last-contribution-block uint u0)

;; Contribution tracking maps
(define-map contribution-history
    uint ;; block-height
    {amount: uint, contributor: principal, total-at-block: uint})

(define-map daily-metrics
    uint ;; day (block-height / 144)
    {contributions: uint, contributors: uint, total-amount: uint})

(define-map contributor-metrics
    principal
    {first-contribution-block: uint, total-contributions: uint, contribution-count: uint})

(define-map campaign-snapshots
    uint ;; snapshot-id
    {block-height: uint, total-raised: uint, contributors: uint, progress-percentage: uint, timestamp: uint})

(define-data-var next-snapshot-id uint u1)
(define-data-var contribution-counter uint u0)

;; Initialize analytics system
(define-public (initialize-analytics)
    (begin
        (asserts! (is-eq tx-sender (var-get campaign-owner)) ERR-UNAUTHORIZED)
        (var-set campaign-creation-block stacks-block-height)
        (var-set analytics-enabled true)
        (ok true)))

;; Record contribution analytics (called internally)
(define-private (record-contribution-analytics (contributor principal) (amount uint))
    (let ((current-day (/ stacks-block-height u144))
          (existing-metrics (default-to {contributions: u0, contributors: u0, total-amount: u0}
                           (map-get? daily-metrics current-day)))
          (contributor-data (default-to {first-contribution-block: stacks-block-height, 
                                       total-contributions: u0, contribution-count: u0}
                          (map-get? contributor-metrics contributor)))
          (is-new-contributor (is-none (map-get? contributor-metrics contributor))))
        (begin
            ;; Update daily metrics
            (map-set daily-metrics current-day {
                contributions: (+ (get contributions existing-metrics) u1),
                contributors: (+ (get contributors existing-metrics) (if is-new-contributor u1 u0)),
                total-amount: (+ (get total-amount existing-metrics) amount)
            })
            
            ;; Update contributor metrics
            (map-set contributor-metrics contributor {
                first-contribution-block: (get first-contribution-block contributor-data),
                total-contributions: (+ (get total-contributions contributor-data) amount),
                contribution-count: (+ (get contribution-count contributor-data) u1)
            })
            
            ;; Record contribution history
            (map-set contribution-history stacks-block-height {
                amount: amount,
                contributor: contributor,
                total-at-block: (var-get total-raised)
            })
            
            ;; Update global analytics
            (if is-new-contributor
                (var-set total-contributors (+ (var-get total-contributors) u1))
                true)
            
            (if (> amount (var-get highest-contribution))
                (var-set highest-contribution amount)
                true)
            
            (if (< amount (var-get lowest-contribution))
                (var-set lowest-contribution amount)
                true)
            
            (var-set last-contribution-block stacks-block-height)
            (var-set contribution-counter (+ (var-get contribution-counter) u1))
            true)))

;; Create campaign snapshot
(define-public (create-campaign-snapshot)
    (let ((snapshot-id (var-get next-snapshot-id))
          (progress (/ (* (var-get total-raised) u100) (var-get campaign-goal))))
        (begin
            (asserts! (var-get analytics-enabled) ERR-ANALYTICS-DISABLED)
            (map-set campaign-snapshots snapshot-id {
                block-height: stacks-block-height,
                total-raised: (var-get total-raised),
                contributors: (var-get total-contributors),
                progress-percentage: progress,
                timestamp: stacks-block-height
            })
            (var-set next-snapshot-id (+ snapshot-id u1))
            (ok snapshot-id))))

;; Enhanced contribute function with analytics
(define-public (contribute-with-analytics (amount uint))
    (let ((current-contribution (default-to {amount: u0, claimed: false} 
            (map-get? contributions tx-sender))))
        (begin
            (asserts! (< stacks-block-height (var-get campaign-deadline)) ERR-CAMPAIGN-ENDED)
            (asserts! (> amount u0) ERR-INVALID-AMOUNT)
            (asserts! (var-get analytics-enabled) ERR-ANALYTICS-DISABLED)
            
            ;; Update contribution mapping
            (map-set contributions tx-sender 
                {amount: (+ (get amount current-contribution) amount),
                 claimed: false})
            
            ;; Update total raised
            (var-set total-raised (+ (var-get total-raised) amount))
            
            ;; Record analytics
            (record-contribution-analytics tx-sender amount)
            
            (ok true))))

;; Get comprehensive campaign analytics
(define-read-only (get-campaign-analytics)
    (let ((campaign-duration (- stacks-block-height (var-get campaign-creation-block)))
          (progress-percentage (/ (* (var-get total-raised) u100) (var-get campaign-goal)))
          (avg-contribution (if (> (var-get total-contributors) u0)
                              (/ (var-get total-raised) (var-get total-contributors))
                              u0))
          (days-remaining (if (> (var-get campaign-deadline) stacks-block-height)
                            (/ (- (var-get campaign-deadline) stacks-block-height) u144)
                            u0)))
        (ok {
            total-raised: (var-get total-raised),
            goal: (var-get campaign-goal),
            progress-percentage: progress-percentage,
            total-contributors: (var-get total-contributors),
            total-contributions: (var-get contribution-counter),
            highest-contribution: (var-get highest-contribution),
            lowest-contribution: (if (< (var-get lowest-contribution) u1000000000000) 
                                   (var-get lowest-contribution) u0),
            average-contribution: avg-contribution,
            campaign-duration-blocks: campaign-duration,
            campaign-duration-days: (/ campaign-duration u144),
            days-remaining: days-remaining,
            blocks-remaining: (if (> (var-get campaign-deadline) stacks-block-height)
                               (- (var-get campaign-deadline) stacks-block-height)
                               u0),
            last-contribution-block: (var-get last-contribution-block),
            analytics-enabled: (var-get analytics-enabled)
        })))

;; Get daily metrics for a specific day
(define-read-only (get-daily-metrics (day uint))
    (ok (map-get? daily-metrics day)))

;; Get contributor analytics
(define-read-only (get-contributor-analytics (contributor principal))
    (let ((metrics (map-get? contributor-metrics contributor))
          (contribution (map-get? contributions contributor)))
        (if (and (is-some metrics) (is-some contribution))
            (let ((metrics-data (unwrap-panic metrics))
                  (contribution-data (unwrap-panic contribution)))
                (ok (some {
                    first-contribution-block: (get first-contribution-block metrics-data),
                    total-contributions: (get total-contributions metrics-data),
                    contribution-count: (get contribution-count metrics-data),
                    current-amount: (get amount contribution-data),
                    claimed-refund: (get claimed contribution-data),
                    participation-duration: (if (> (var-get last-contribution-block) 
                                                 (get first-contribution-block metrics-data))
                                              (- (var-get last-contribution-block) 
                                                 (get first-contribution-block metrics-data))
                                              u0)
                })))
            (ok none))))

;; Get campaign snapshot by ID
(define-read-only (get-campaign-snapshot (snapshot-id uint))
    (ok (map-get? campaign-snapshots snapshot-id)))

;; Get contribution history for a specific block
(define-read-only (get-contribution-history (target-block uint))
    (ok (map-get? contribution-history target-block)))

;; Get campaign performance metrics
(define-read-only (get-performance-metrics)
    (let ((current-day (/ stacks-block-height u144))
          (campaign-start-day (/ (var-get campaign-creation-block) u144))
          (campaign-days (if (>= current-day campaign-start-day) 
                          (- current-day campaign-start-day) u0))
          (daily-average (if (> campaign-days u0)
                          (/ (var-get total-raised) campaign-days)
                          u0))
          (contributor-engagement (if (> (var-get total-contributors) u0)
                                   (/ (var-get contribution-counter) (var-get total-contributors))
                                   u0))
          (progress-percentage (/ (* (var-get total-raised) u100) (var-get campaign-goal)))
          (success-calc (+ progress-percentage (/ daily-average u10000)))
          (success-probability (if (> success-calc u100) u100 success-calc)))
        (ok {
            campaign-days: campaign-days,
            daily-average-raised: daily-average,
            contributor-engagement-rate: contributor-engagement,
            funding-velocity: (if (> campaign-days u0)
                               (/ (* (var-get total-raised) u100) 
                                  (* (var-get campaign-goal) campaign-days))
                               u0),
            success-probability: success-probability,
            total-snapshots: (- (var-get next-snapshot-id) u1)
        })))

;; Toggle analytics system
(define-public (toggle-analytics (enable bool))
    (begin
        (asserts! (is-eq tx-sender (var-get campaign-owner)) ERR-UNAUTHORIZED)
        (var-set analytics-enabled enable)
        (ok enable)))

;; Get recent activity (last 10 blocks of contributions)
(define-read-only (get-recent-activity)
    (let ((recent-blocks (list 
            (- stacks-block-height u0) (- stacks-block-height u1) (- stacks-block-height u2)
            (- stacks-block-height u3) (- stacks-block-height u4) (- stacks-block-height u5)
            (- stacks-block-height u6) (- stacks-block-height u7) (- stacks-block-height u8)
            (- stacks-block-height u9))))
        (ok {
            recent-contributions: (filter is-contribution-block recent-blocks),
            total-recent-blocks: (len recent-blocks)
        })))

;; Helper function to check if a block has contributions
(define-private (is-contribution-block (target-block uint))
    (is-some (map-get? contribution-history target-block)))
