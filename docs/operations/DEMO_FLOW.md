# Essentials+ Office demo flow

## Data policy

Use only the fictitious identities `demo.alex` and `demo.riley`, display names
“Alex Example” and “Riley Example”, and mailboxes below
`workspace-demo.invalid`. The `.invalid` top-level domain is reserved and must
not receive public DNS or mail. Generate passwords locally and keep them out of
Git, screenshots, recordings, and test reports.

No seed is run automatically. This prevents a production reconciliation from
creating demo accounts. Create the identities only on an instance explicitly
classified as demo, and remove them with their data after acceptance.

## Preconditions

- Base healthcheck and WebDAV round-trip pass.
- Encrypted offsite backup and disposable restore pass.
- All declared apps are enabled and inventoried.
- Collabora discovery, WOPI restrictions, and two-user editing pass.
- Talk chat/P2P passes; TURN is required only after its external acceptance.
- A private demo mailcow delivers locally while outbound TCP 25 is blocked.

## Acceptance journey

1. Alex uploads an invented ODT file named `Project Aurora Demo.odt`.
2. Alex shares it with Riley; both edit distinct paragraphs simultaneously and
   save.
3. Alex shares the file into a Talk room named `Aurora Demo` and Riley opens it
   from chat.
4. Riley creates an invented task “Review Aurora budget assumptions” in
   Nextcloud Tasks and a note “Aurora demo decisions” in Notes.
5. Riley creates a Deck card linked to the same fictitious work item and adds a
   short Collectives page. Calendar/Contacts/Tasks remain in Nextcloud.
6. Alex sends a purely local message from
   `demo.alex@workspace-demo.invalid` to
   `demo.riley@workspace-demo.invalid`; Riley reads it in Nextcloud Mail.
7. Restart Collabora and the Nextcloud app container separately. Reopen the
   document, confirm file versions, chat history, task/note, and local message.
8. On an explicitly disposable instance, run the Appointments demo seed for
   “Physiotherapie Beispiel”. Book one fictional slot, verify the internal
   calendar and queued confirmation, cancel through the fragment-token link,
   and confirm that the slot becomes available again. A parallel request for
   the same slot must receive a conflict rather than a second booking.

Record pass/fail, UTC timestamp, component versions, browser versions, source
network class, and resource peaks. Do not record message bodies, access tokens,
TURN candidates, cookies, credentials, or internal addresses.
