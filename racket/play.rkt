#lang racket

(require racket/serialize)

;; MODEL ==========================================================================

(serializable-struct exit (room-id key lock-msg))
(serializable-struct item (descrip equip-type strength))
(serializable-struct recp (ingredients tools results))
(serializable-struct room (descrip items exits) #:mutable)
(serializable-struct body (room-id items equip hp msg-q) #:transparent #:mutable)

;; CORE ===========================================================================

(define (symbol<? s1 s2)
  (string<? (symbol->string s1) (symbol->string s2)))

(define (where hsh getter comparer val)
  (and hsh 
       (make-hash 
        (filter 
         (compose (curryr comparer val)
                  getter)
         (hash->list hsh)))))

(define (format-hash formatter objs)
  (let ([strs (and objs (< 0 (hash-count objs)) (hash-map objs formatter))])
    (or (and strs (string-join strs "\n\t")) "none")))

;; CONTROLLER =====================================================================

(define (get-people-in id)
  (where bodies (compose body-room-id cdr) equal? id))

(define (item-description k v)
  (let* ([i (hash-ref item-catalogue k #f)]
         [desc (and i (item-descrip i))])
    (format "~a ~a - ~a" v k (or desc "(UNKNOWN)"))))

(define (equip-description k v)
  (let* ([i (hash-ref item-catalogue v #f)]
         [desc (and i (item-descrip i))])
    (format "(~a) ~a - ~a" k v (or desc "(UNKNOWN)"))))

(define (room-people-description k v)
  (let* ([bdy (and k (hash-ref bodies k #f))]
         [hp (and bdy (body-hp bdy))]
         [extra (and hp (if (> hp 0) "" " (KNOCKED OUT)"))])
    (format "~a~a" k extra)))

(define (room-filename id)
  (format "~a.room" id))

(define (room-exit-filename x)
  (room-filename (exit-room-id x)))

(define (exit-description k v)
  (let* ([filename (and v (room-exit-filename v))]
         [exists (and filename (file-exists? filename))]
         [extra (if exists "" " (UNDER CONSTRUCTION)")])
    (format "~a~a" k extra)))

(define (prepare-room)
  (let* ([rm (deserialize (read))]
         [mitms (where (room-items rm) cdr > 0)])
    (set-room-items! rm (or mitms (make-hash)))
    rm))

(define (read-room id)
  (let* ([filename (string-append (symbol->string id) ".room")]
         [exists (file-exists? filename)])
    (and exists
         (with-input-from-file filename prepare-room))))

(define (get-room id)
  (let ([rm (hash-ref! current-rooms id (curry read-room id))])
    (unless rm (displayln (format "room \"~a\" does not exist." id)))
    rm))

(define (write-room id rm)
  (let ([filename (and id rm (room-filename id))])
    (when filename 
      (with-output-to-file
          filename
        (curry write (serialize rm))
        #:mode 'text
        #:exists 'replace))))

(define (help-description sym)
  (let* ([exists (findf (curry equal? sym) current-cmds)]
         [cmd (and exists (eval sym))]
         [arity (and cmd (sub1 (procedure-arity cmd)))]
         [params (and arity (sequence-map (curry format "p~a") (in-range 0 arity)))])
    (string-join (cons (symbol->string sym) 
                       (if params
                           (sequence->list params)
                           '(" - (UNKOWN)"))))))

(define (move-item itm from to act-name loc-name)
  (if (hash-ref from itm #f)
      (begin
        (hash-update! from itm sub1)
        (when (= 0 (hash-ref from itm))
          (hash-remove! from itm))
        (hash-update! to itm add1 0)
        (displayln (format "You ~a the ~a" act-name itm)))
      (displayln (format "There is no ~a ~a" itm loc-name))))

(define (inform-user bdy-id msg from-id)
  (let ([bdy (and bdy-id (hash-ref bodies bdy-id #f))])
    (when bdy
      (set-body-msg-q! 
       bdy
       (cons (list from-id msg)
             (body-msg-q bdy))))))

(define (inform-users usrs msg from-id)
  (for ([p (hash->list usrs)])
    (inform-user (car p) '(quit) from-id)))

(define (hash-satisfies? from to greater-than?)
  (andmap identity 
          (for/list ([c (hash->list to)])
            (>= (hash-ref from (car c) 0) 
                (cdr c)))))


;; COMMANDS =======================================================================

(define (quit bdy-id)
  (let* ([bdy (and bdy-id (hash-ref bodies bdy-id #f))])
    (when bdy
      (hash-remove! bodies bdy-id)
      (inform-users bodies '(quit) bdy-id)
      (when (equal? bdy-id 'player) (set! done #t)))))

(define (help bdy-id)
  (displayln (format "Available commands:
\t~a" (string-join (map help-description current-cmds) "\n\t"))))

(define (look bdy-id)
  (let* ([bdy (and bdy-id (hash-ref bodies bdy-id #f))]
         [id (and bdy (body-room-id bdy))]
         [rm (and id (get-room id))]
         [items (and rm (room-items rm))]
         [people (and id (get-people-in id))]
         [exits (and rm (room-exits rm))])
    (when rm
      (displayln (format "ROOM: ~a

ITEMS:
\t~a

PEOPLE:
\t~a

EXITS:
\t~a
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-" 
                         (room-descrip rm)
                         (format-hash item-description items)
                         (format-hash room-people-description (where people car (compose not equal?) bdy-id))
                         (format-hash exit-description exits))))))

(define (move bdy-id dir)
  (let* ([bdy (and bdy-id (hash-ref bodies bdy-id #f))]
         [id (and bdy (body-room-id bdy))]
         [rm (and id (get-room id))]
         [people (and id (get-people-in id))]
         [exits (room-exits rm)]
         [x (and exits (hash-ref exits dir #f))]
         [exists (and x (file-exists? (room-exit-filename x)))]
         [key (and exists (exit-key x))]
         [items (and bdy (body-items bdy))]
         [good (and items x (or (not key) (and key (hash-ref items key #f))))])
    (if good
        (begin
          (set-body-room-id! bdy (exit-room-id x))
          (when people 
            (inform-users people '(entered) bdy-id))
          (look bdy-id))
        (if key
            (displayln (exit-lock-msg x))
            (displayln "You can't go that way")))))

(define (north bdy-id) (move bdy-id 'north))
(define (east bdy-id) (move bdy-id 'east))
(define (south bdy-id) (move bdy-id 'south))
(define (west bdy-id) (move bdy-id 'west))

(define (take bdy-id itm)
  (let* ([bdy (and bdy-id (hash-ref bodies bdy-id #f))]
         [id (and bdy (body-room-id bdy))]
         [people (and id (get-people-in id))]
         [rm (and id (get-room id))]
         [items (and bdy (body-items bdy))])
    (when rm
      (move-item itm (room-items rm) items "picked up" "here")
      (when people
        (inform-users people (list 'take itm) bdy-id)))))

(define (drop bdy-id itm)
  (let* ([bdy (and bdy-id (hash-ref bodies bdy-id #f))]
         [id (and bdy (body-room-id bdy))]
         [people (and id (get-people-in id))]
         [rm (and id (get-room id))]
         [items (and bdy (body-items bdy))])
    (when rm 
      (move-item itm 
                 items
                 (room-items rm)
                 "dropped"
                 "in your inventory")
      (when people
        (inform-users people (list 'drop itm) bdy-id)))))

(define (give bdy-id person itm)
  (let* ([bdy (and bdy-id (hash-ref bodies bdy-id #f))]
         [id (and bdy (body-room-id bdy))]
         [rm (and id (get-room id))]
         [people (get-people-in id)]
         [target (hash-ref people person #f)]
         [items (and bdy (body-items bdy))])
    (if target
        (move-item itm
                   items
                   (body-items target)
                   (format "gave to ~a" person)
                   "in your inventory")
        (begin
          (displayln (format "~a is not here" person))
          (inform-users people (list 'gave person itm) bdy-id)))))

(define (make bdy-id rcp-id)
  (let* ([bdy (and bdy-id (hash-ref bodies bdy-id #f))]
         [rm-id (and bdy (body-room-id bdy))]
         [people (and rm-id (get-people-in rm-id))]
         [items (and bdy (body-items bdy))]
         [rcp (and rcp-id (hash-ref recipes rcp-id #f))]
         [ingr (and rcp (recp-ingredients rcp))]
         [tools (and rcp (recp-tools rcp))]
         [res (and rcp (hash-copy (recp-results rcp)))]
         [have-all-ingr (and items ingr (hash-satisfies? items ingr >))]
         [have-all-tool (and items tools (hash-satisfies? items tools >))])
    (if (and have-all-ingr have-all-tool)
        (begin
          (for ([i (hash->list ingr)])
            (hash-update! items (car i) (curry - (cdr i)))
            (when (= 0 (hash-ref items (car i)))
              (hash-remove! items (car i)))
            (when people
              (inform-users people (list 'make rcp-id) bdy-id))
            (displayln (format "~a ~a(s) removed from inventory" (cdr i) (car i))))
          (for ([i (hash->list res)])
            (hash-update! items (car i) (curry + (cdr i)) 0)
            (displayln (format "You created ~a ~a(s)" (cdr i) (car i)))))
        (if (not have-all-ingr)
            (displayln "You don't have all of the ingredients")
            (displayln "You don't have all of the tools")))))

(define (inv bdy-id)
  (let* ([bdy (and bdy-id (hash-ref bodies bdy-id #f))]
         [items (and bdy (body-items bdy))]
         [equip (and bdy (body-equip bdy))])
    (when items
      (display "\t")
      (displayln (format-hash item-description items))
      (display "\n\t")
      (displayln (format-hash equip-description equip)))))

(define (equip bdy-id item-id)
  (let* ([bdy (and bdy-id (hash-ref bodies bdy-id #f))]
         [items (and bdy (body-items bdy))]
         [itm (and items item-id (hash-ref item-catalogue item-id #f))]
         [itm-qpt (and itm (item-equip-type itm))]
         [qp (and bdy (body-equip bdy))]
         [cur (and itm-qpt qp (hash-ref qp itm-qpt #f))]
         [good (and itm-qpt (not (equal? itm-qpt 'none)))])
    (if good
        (begin 
          (when cur 
            (hash-update! items cur add1 0)
            (hash-remove! qp itm-qpt))
          (hash-set! qp itm-qpt item-id)
          (hash-update! items item-id sub1)
          (when (= 0 (hash-ref items item-id))
            (hash-remove! items item-id))
          (displayln (format "You equiped the ~a as a ~a." item-id itm-qpt)))
        (if itm
            (displayln (format "You can't equip the ~a." item-id))
            (displayln (format "You don't have the ~a." item-id))))))

(define (remove bdy-id item-id)
  (let* ([bdy (and bdy-id (hash-ref bodies bdy-id #f))]
         [items (and bdy (body-items bdy))]
         [qp (and bdy (body-equip bdy))]
         [cur (and qp (where qp cdr equal? item-id))]
         [itm-qpt (and cur (caar (hash->list cur)))]
         [good (and items cur)])
    (if good
        (begin 
          (hash-update! items item-id add1 0)
          (hash-remove! qp itm-qpt)
          (displayln (format "You removed the ~a from the ~a slot." item-id itm-qpt)))
        (displayln (format "You don't have the ~a equipped." item-id)))))

(define (attack bdy-id target-id)
  (let* ([bdy (and bdy-id (hash-ref bodies bdy-id #f))]
         [eqp (and bdy (body-equip bdy))]
         [wpn-id (and eqp (hash-ref eqp 'tool #f))]
         [wpn (and wpn-id (hash-ref item-catalogue wpn-id #f))]
         [wpn-desc (or (and wpn (format "the ~a" wpn-id)) "nothing")]
         [atk (or (and wpn (item-strength wpn)) 1)]
         [loc (and bdy (body-room-id bdy))]
         [people (and loc (get-people-in loc))]
         [trg (and target-id (hash-ref people target-id #f))])
    (if trg
        (begin 
          (set-body-hp! trg (- (body-hp trg) atk))
          (inform-users people (list 'attack target-id) bdy-id)
          (inform-user target-id (list 'damage atk) bdy-id)
          (displayln (format "You attack ~a with ~a for ~a dmg." target-id wpn-desc atk)))
        (displayln (format "There is no ~a to attack." target-id)))))

;; INPUT AND TOKENIZING ===========================================================

(define (do-command bdy-id str)
  (displayln str)
  (when (positive? (string-length str))
    (let* ([tokens (map string->symbol (string-split str " "))]
           [params (rest tokens)]
           [cmd (first tokens)]
           [exists (and cmd (member cmd current-cmds))]
           [proc (and exists (eval cmd))]
           [arg-count (or (and proc (sub1 (procedure-arity proc))) 0)])
      (if exists
          (if (= (length params) arg-count)
              (apply proc (cons bdy-id params))
              (if (< (length params) arg-count)
                  (displayln "not enough parameters")
                  (displayln "too many parameters")))
          (displayln (format "I do not understand \"~a\"." cmd))))))

(define (prompt bdy)
  (display (format "~a :> " (body-hp bdy)))
  (read-line))

(define (run)
  (set! done #f)
  (let loop ()
    (for ([kv (hash->list bodies)]
          #:break done)
      (let* ([bdy-id (car kv)]
             [bdy (cdr kv)]
             [io (and bdy-id (hash-ref io-ports bdy-id #f))])
        (when io
        (parameterize 
            ([current-input-port (car io)]
             [current-output-port (cdr io)])
          (if (> (body-hp bdy) 0)
              (begin
                (displayln bdy-id)
                (unless (equal? bdy-id 'player)
                  (random-command))
                (do-command bdy-id (string-downcase (prompt bdy))))
              (displayln "Knocked out!")))))
    (unless done (loop)))))

;; STATE ==========================================================================

(define current-rooms (make-hash))
(define current-cmds (sort '(quit 
                             help
                             look 
                             take drop give inv
                             make 
                             equip remove 
                             attack
                             north south east west) symbol<?))
(define equip-types '(none
                      head
                      eyes
                      shoulders 
                      torso
                      pants belt shirt
                      biceps forearms hands
                      thighs calves feet
                      tool
                      necklace 
                      left-bracelet right-bracelet))
(define item-catalogue
  (hash 'sword (item "a rusty sword" 'tool 10)
        'bird (item "definitely a bird" 'none 0)
        'dead-bird (item "maybe he's pining for the fjords?" 'none 0)
        'feather (item "bird-hair" 'none 0)
        'rock (item "definitely not a bird" 'none 2)
        'garbage (item "some junk" 'none 0)
        'shovel (item "used to butter bread" 'tool 5)))
(define recipes
  (hash 'dead-bird (recp (hash 'bird 1)
                         (hash 'sword 1)
                         (hash 'dead-bird 1 'feather 5))))
(define bodies (hash-copy (hash 'player (body 'test (make-hash) (make-hash) 10 '())
                                'dave (body 'test (make-hash) (make-hash) 10 '())
                                'mark (body 'test2 (make-hash) (make-hash) 10 '())
                                'carl (body 'test3 (make-hash) (make-hash) 10 '()))))

(define (greep) (call-with-values (λ () (make-pipe)) cons))
(define io-ports (hash 'player (cons (current-input-port) (current-output-port))
                       'dave (greep)
                       'mark (greep)
                       'carl (greep)))

(define done #f)

(define (random-command)
  (define cmds '("north" "south" "east" "west" "attack player"))
  (displayln (list-ref cmds (random (length cmds)))))

;; TESTING ========================================================================

(define (create-test-rooms)
  (write-room 'test (room "a test room

There is not a lot to see here.
This is just a test room.
It's meant for testing.
Nothing more.
Goodbye."
                          (hash 'sword 1
                                'bird 1
                                'rock 5
                                'garbage 0
                                'orb 1
                                'hidden 0)
                          (hash 'north (exit 'test2 #f #f)
                                'east (exit 'test3 #f #f)
                                'south (exit 'test4 'feather "you need a feather")
                                'west #f)))
  
  (write-room 'test2 (room "another test room

Keep moving along"
                           #f
                           (hash 'south (exit 'test #f #f))))
  
  (write-room 'test3 (room "a loop room

it's probably going to work"
                           #f
                           (hash 'south (exit 'test5 #f #f))))
  
  (write-room 'test4 (room "locked room

This room was locked with the bird"
                           #f
                           (hash 'north (exit 'test #f #f))))
  
  (write-room 'test5 (room "a loop room, 2

it's probably going to work"
                           #f
                           (hash 'west (exit 'test4 #f #f)))))

(define (test)
  (create-test-rooms)
  (let-values ([(in out) (make-pipe)])
    (parameterize ([current-input-port in])
      (displayln "
look
take something
take garbage
take orb
take hidden
take rock
take rock
take rock
take rock
take rock
take sword
give tom sword
give dave sword
give dave something
give tom something
look
north
look
south
look
west
look
south
take bird
south
make dead-bird
drop dead-bird
drop feather
drop feather
drop feather
drop feather
look
south
look
drop orb
look
north
south
quit" out)
      (run))))

(define (test-equip)
  (take 'player 'sword)
  (equip 'player 'sword)
  (inv 'player)
  (equip 'player 'shovel)
  (inv 'player)
  (remove 'player 'shovel)
  (inv 'player))