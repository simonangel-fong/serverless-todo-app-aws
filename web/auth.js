// auth.js — Cognito authentication + authenticated API helper.
//
// Uses amazon-cognito-identity-js (loaded via CDN in each page) against the user
// pool + app client configured in config.js. The app client uses USER_SRP_AUTH,
// so passwords are never sent in the clear.
//
// Every page includes this file and calls:
//   Auth.requireLogin()  -> redirect to login.html if not signed in
//   apiFetch(path, opts) -> fetch against the API with the ID token attached
//
// The API authorizer (Cognito) validates the ID token; the Lambda reads the
// caller's `sub` from the claims (see docs/api-contract.md §1).

const Auth = (() => {
  const cfg = window.APP_CONFIG;

  const userPool = new AmazonCognitoIdentity.CognitoUserPool({
    UserPoolId: cfg.COGNITO_POOL_ID,
    ClientId: cfg.COGNITO_CLIENT_ID,
  });

  function currentUser() {
    return userPool.getCurrentUser();
  }

  // Resolve the current valid ID token, refreshing via the session if needed.
  function getIdToken() {
    return new Promise((resolve, reject) => {
      const user = currentUser();
      if (!user) return reject(new Error("Not signed in"));
      user.getSession((err, session) => {
        if (err || !session.isValid()) return reject(err || new Error("Session invalid"));
        resolve(session.getIdToken().getJwtToken());
      });
    });
  }

  function signIn(email, password) {
    return new Promise((resolve, reject) => {
      const user = new AmazonCognitoIdentity.CognitoUser({ Username: email, Pool: userPool });
      const details = new AmazonCognitoIdentity.AuthenticationDetails({
        Username: email,
        Password: password,
      });
      user.authenticateUser(details, {
        onSuccess: () => resolve(),
        onFailure: (err) => reject(err),
      });
    });
  }

  function signUp(email, password) {
    return new Promise((resolve, reject) => {
      const attributes = [
        new AmazonCognitoIdentity.CognitoUserAttribute({ Name: "email", Value: email }),
      ];
      userPool.signUp(email, password, attributes, null, (err) => {
        if (err) return reject(err);
        resolve();
      });
    });
  }

  // Confirm the sign-up with the emailed verification code.
  function confirm(email, code) {
    return new Promise((resolve, reject) => {
      const user = new AmazonCognitoIdentity.CognitoUser({ Username: email, Pool: userPool });
      user.confirmRegistration(code, true, (err) => {
        if (err) return reject(err);
        resolve();
      });
    });
  }

  function signOut() {
    const user = currentUser();
    if (user) user.signOut();
    window.location.href = "login.html";
  }

  // Gate a page: redirect to login unless there's a valid session.
  async function requireLogin() {
    try {
      await getIdToken();
    } catch {
      window.location.href = "login.html";
    }
  }

  return { userPool, currentUser, getIdToken, signIn, signUp, confirm, signOut, requireLogin };
})();

// Authenticated fetch: attaches the ID token, targets the configured API base,
// and sends the caller to login on 401 (expired/invalid token).
async function apiFetch(path, options = {}) {
  const token = await Auth.getIdToken();
  const headers = Object.assign(
    { "Content-Type": "application/json", Authorization: token },
    options.headers || {}
  );
  const res = await fetch(`${window.APP_CONFIG.API_BASE_URL}${path}`, { ...options, headers });

  if (res.status === 401) {
    Auth.signOut(); // token no longer valid — force re-login
    throw new Error("Session expired");
  }
  return res;
}
