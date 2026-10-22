# FMS cookie login

The API reads the HttpOnly cookie named FMS_id and looks up its positive integer
value directly against active FMS account UserId values. For example, FMS_id=129
loads account 129, using the username, name, role, and department from the database.
No username or email is hardcoded. No JWT configuration or Main_Users lookup is used.

The live frontend calls GET /api/auth/session with credentials, then routes to
/dashboard for a matching active account or /404 otherwise. Missing, malformed,
unknown, or inactive IDs cause API requests to return HTTP 404.
The API attaches the FMS ID as the NameIdentifier claim and logs the ID.

The browser must send the cookie to the API host: check its Domain and Path
(Path=/), and use HTTPS for a Secure cookie. A cookie scoped to cathaylandinc.com
will not be sent to localhost or an IP address. Credentialed CORS permits
https://fms.cathaylandinc.com and the configured localhost development origins.

Security limitation: a plain numeric cookie is editable by the client. HttpOnly
prevents JavaScript access but does not protect the value against impersonation.
This legacy integration does not provide cryptographic authentication; a signed
cookie or server-validated upstream session is needed to establish identity securely.
Existing workflow authorization and caller-supplied user parameters remain in place.

Sign-out clears frontend identity, but does not clear the upstream cookie.
Refreshing or reopening can therefore sign the user back in.
