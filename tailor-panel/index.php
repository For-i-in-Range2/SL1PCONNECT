<?php
// secrets en clair
$host = getenv('DB_HOST') ?: 'db-velvet';
$db   = getenv('DB_NAME') ?: 'velvet';
$user = getenv('DB_USER') ?: 'velvet';
$pass = getenv('DB_PASSWORD') ?: 'velvet';
$port = getenv('DB_PORT') ?: '5432';

// connexion avec retry (postgres peut demarrer apres)
$pdo = null;
for ($i = 0; $i < 15; $i++) {
    try {
        $pdo = new PDO("pgsql:host=$host;port=$port;dbname=$db", $user, $pass);
        break;
    } catch (Exception $e) {
        sleep(2);
    }
}

session_start();

// login en dur, identifiants faibles
if (isset($_POST['login'])) {
    if (($_POST['username'] ?? '') === 'admin' && ($_POST['password'] ?? '') === 'admin') {
        $_SESSION['auth'] = true;
    } else {
        $error = "Identifiants invalides";
    }
}
if (isset($_GET['logout'])) {
    session_destroy();
    header('Location: /');
    exit;
}

function h($s) { return htmlspecialchars((string)($s ?? ''), ENT_QUOTES); }
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
 pre{background:#f4f4f4;padding:8px;overflow:auto}
</style>
</head>
<body>
<h1>SL1PCONNECT &mdash; Back-office (tailor-panel)</h1>

<?php if (empty($_SESSION['auth'])): ?>
  <?php if (!empty($error)) echo "<p style='color:#C00000'>" . h($error) . "</p>"; ?>
  <form method="post">
    <input name="username" placeholder="utilisateur">
    <input name="password" type="password" placeholder="mot de passe">
    <button name="login" value="1">Connexion</button>
  </form>
<?php else: ?>
  <p><a href="?logout=1">Deconnexion</a></p>
  <h2>Recherche d'utilisateurs</h2>
  <form method="get">
    <input name="q" value="<?php echo h($_GET['q'] ?? ''); ?>" placeholder="email...">
    <button>Rechercher</button>
  </form>
  <?php
    // requete construite par concatenation directe
    $q = $_GET['q'] ?? '';
    $sql = "SELECT id, email, role FROM users WHERE email LIKE '%$q%'";
    echo "<pre>" . h($sql) . "</pre>";
    try {
        $rows = $pdo->query($sql);
        echo "<table><tr><th>id</th><th>email</th><th>role</th></tr>";
        foreach ($rows as $r) {
            echo "<tr><td>" . h($r['id']) . "</td><td>" . h($r['email']) .
                 "</td><td>" . h($r['role']) . "</td></tr>";
        }
        echo "</table>";
    } catch (Exception $e) {
        echo "<p style='color:#C00000'>Erreur SQL : " . h($e->getMessage()) . "</p>";
    }
  ?>
<?php endif; ?>
</body>
</html>
