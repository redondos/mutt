# -*- muttrc -*-
#
# List of folders that are considered to be "mailboxes" (folders that
# receive incoming mail).
#

mailboxes "imaps://aolivera@imap.gmail.com:993/INBOX"
mailboxes "imaps://aolivera@imap.gmail.com:993/NComputing"

