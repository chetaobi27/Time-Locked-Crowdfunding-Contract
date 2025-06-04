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
