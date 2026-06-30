<?php
/**
 * tailor-panel – version corrigee
 * Corrections :
 *   1. Mot de passe DB lu depuis /run/secrets/ (Docker Secret)
 *   2. Injection SQL corrigee : requetes preparees (PDO)
 *   3. Auth contre la BDD avec password_verify() (bcrypt)
 *   4. Session renforcee (regenerate ID, cookie httponly/samesite)
 */

// ── Lecture du secret Docker ──────────────────────────────────────
function read_secret(string $name): string {
    $path = "/run/secrets/$name";
    if (is_readable($path)) {
        return trim(file_get_contents($path));
    }
    // Fallback pour tests locaux sans Docker Secrets
    return (string)(getenv(strtoupper($name)) ?: '');
}

// ── Connexion BDD ─────────────────────────────────────────────────
$host = getenv('DB_HOST') ?: 'db-velvet';
$db   = getenv('DB_NAME') ?: 'velvet';
$user = getenv('DB_USER') ?: 'velvet';
$pass = read_secret('db_password');   // Correction #1 : secret, pas env var
$port = getenv('DB_PORT') ?: '5432';

$pdo = null;
for ($i = 0; $i < 15; $i++) {
    try {
        $pdo = new PDO("pgsql:host=$host;port=$port;dbname=$db", $user, $pass, [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,  // requetes vraiment preparees
        ]);
        break;
    } catch (Exception $e) {
        sleep(2);
    }
}

// ── Session securisee ─────────────────────────────────────────────
ini_set('session.cookie_httponly', '1');
ini_set('session.cookie_samesite', 'Strict');
ini_set('session.use_strict_mode', '1');
session_start();

// ── Authentification ──────────────────────────────────────────────
if (isset($_POST['login']) && $pdo) {
    $email    = $_POST['username'] ?? '';
    $password = $_POST['password'] ?? '';

    // Correction #3 : verification contre la BDD, jamais de login en dur
    $stmt = $pdo->prepare("SELECT id, password_hash, role FROM users WHERE email = ?");
    $stmt->execute([$email]);
    $u = $stmt->fetch();

    if ($u && password_verify($password, $u['password_hash'])) {
        // Regeneration de l'ID de session (prevention de fixation de session)
        session_regenerate_id(true);
        $_SESSION['auth'] = true;
        $_SESSION['role'] = $u['role'];
        $_SESSION['uid']  = $u['id'];
    } else {
        $error = "Identifiants invalides";
    }
}

if (isset($_GET['logout'])) {
    session_destroy();
    header('Location: /');
    exit;
}

// ── Endpoint de healthcheck ───────────────────────────────────────
if ($_SERVER['REQUEST_URI'] === '/health') {
    header('Content-Type: application/json');
    echo json_encode(['status' => 'ok', 'service' => 'tailor-panel']);
    exit;
}

function h($s): string {
    return htmlspecialchars((string)($s ?? ''), ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
?>
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title>SL1P Tailor Panel</title>
<style>
 body{font-family:system-ui,sans-serif;margin:2rem auto;max-width:820px;color:#222}
 h1{color:#1F3864} table{border-collapse:collapse;width:100%;margin-top:1rem}
 td,th{border:1px solid #ccc;padding:6px;text-align:left}
 input{padding:6px;margin-right:.3rem} button{padding:6px 12px}
 .note{background:#e8f4e8;border-left:4px solid #2a7a2a;padding:8px;margin:.5rem 0}
</style>
</head>
<body>
<h1>SL1PCONNECT &mdash; Back-office (tailor-panel)</h1>

<?php if (empty($_SESSION['auth'])): ?>
  <?php if (!empty($error)) echo "<p style='color:#C00000'>" . h($error) . "</p>"; ?>
  <form method="post">
    <input name="username" type="email" placeholder="email" required>
    <input name="password" type="password" placeholder="mot de passe" required>
    <button name="login" value="1">Connexion</button>
  </form>
<?php else: ?>
  <p>Role : <strong><?php echo h($_SESSION['role']); ?></strong> &mdash;
     <a href="?logout=1">Deconnexion</a></p>

  <h2>Recherche d'utilisateurs</h2>
  <form method="get">
    <input name="q" value="<?php echo h($_GET['q'] ?? ''); ?>" placeholder="email...">
    <button>Rechercher</button>
  </form>

  <?php
    // Correction #2 : requete preparee – plus d'injection SQL possible
    $q = $_GET['q'] ?? '';
    if ($q !== '' && $pdo) {
        try {
            $stmt = $pdo->prepare(
                "SELECT id, email, role FROM users WHERE email LIKE ?"
            );
            $stmt->execute(["%$q%"]);
            $rows = $stmt->fetchAll();

            echo "<table><tr><th>id</th><th>email</th><th>role</th></tr>";
            foreach ($rows as $r) {
                echo "<tr><td>" . h($r['id']) . "</td><td>" . h($r['email']) .
                     "</td><td>" . h($r['role']) . "</td></tr>";
            }
            echo "</table>";
        } catch (Exception $e) {
            echo "<p style='color:#C00000'>Erreur SQL.</p>";
            // Ne jamais afficher $e->getMessage() en prod (fuite d'info)
        }
    }
  ?>
<?php endif; ?>
</body>
</html>
