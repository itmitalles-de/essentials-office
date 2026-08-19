# Excluded mail-platform boundary

Essentials+ Office does not install or operate mailcow. Mail is limited to the
Nextcloud Mail IMAP/SMTP integration boundary. The files in this directory are
retained historical compatibility material and must not be interpreted as an
approved deployment, module, production mail platform, or current task.

As of 2026-08-19, repository inspection at base commit `17081f2` found no
evidence of an approved mail host, current DNS/PTR/port acceptance, deployed
mailcow checkout, production mailbox, or delivery test. That is an `unknown` or
`not deployed` result, not an instruction to provision infrastructure.

Existing host/DNS checks and the recorded upstream pin may be used only in a
separately authorized future mail-platform project. They are not invoked by the
default Compose model, the module controller, or this operating-gates branch.
No mail host may share the Nextcloud database, secrets, data root, backup, or
recovery lifecycle.

Within Essentials+ Office, the only repository-safe mail evidence is the
synthetic TLS IMAP/SMTP fixture. It proves a bounded protocol/health contract;
it does not prove Nextcloud Mail account configuration, authentication against
a real provider, mail delivery, DNS reputation, or production operation.
