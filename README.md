# YxxgSxxl Music Downloader

`music_dl.bat` est un outil Windows qui récupère l’audio d’un titre ou d’une playlist depuis un lien pris en charge par `yt-dlp`. Le terminal guide la saisie du lien, puis une fenêtre Windows permet de choisir le dossier de destination.

## Prérequis

- Windows avec l’invite de commandes (`cmd.exe`) et Windows PowerShell.
- `yt-dlp`, `ffmpeg` et `ffprobe` accessibles depuis le terminal.
- Pour la prise en charge de YouTube, un exécutable `yt-dlp` qui inclut `yt-dlp-ejs` et un moteur JavaScript compatible, par exemple Deno. [Dépendances de yt-dlp](https://github.com/yt-dlp/yt-dlp#dependencies)

Sous Windows, tu peux installer les outils avec WinGet.

```powershell
winget install --id yt-dlp.yt-dlp --exact --source winget
winget install --id yt-dlp.FFmpeg --exact --source winget
winget install --id DenoLand.Deno --exact --source winget
```

Dans un nouveau terminal, vérifie que `yt-dlp --version`, `ffmpeg -version` et `ffprobe -version` répondent.

## Utilisation

Depuis le dossier du script, lance la commande suivante dans PowerShell ou dans l’invite de commandes.

```powershell
.\music_dl.bat
```

Colle un lien que tu es autorisé à télécharger, puis choisis un dossier de destination. Si le nom d’un dossier est déjà pris, le script ajoute un suffixe comme `(2)`. Les pistes d’une playlist sont numérotées et le format audio dépend de la source.

Le dossier `_assets` contient le raccourci vers la page d’origine et, si elle est disponible, la pochette. Le script peut récupérer l’icône du site via Google et la mettre en cache dans `%LOCALAPPDATA%\MusicDownloader\icons`.

Appuie sur `Q` au menu principal pour quitter. Si le script signale un échec après le début d’un téléchargement, note le chemin du dossier de travail affiché pour retrouver les fichiers déjà récupérés. Ce dossier se trouve dans la destination choisie.

## Mise à jour de yt-dlp

À chaque lancement, le script compare une fois la version stable installée à la dernière version stable publiée. Le menu affiche le résultat de la vérification avant la saisie du premier lien. Si une mise à jour est disponible, réponds `O` pour l’installer ou appuie sur Entrée pour garder ta version. Une vérification en ligne indisponible laisse le menu accessible.

Le script utilise WinGet pour une installation reconnue comme gérée par WinGet. Pour les autres installations, il demande à `yt-dlp` d’utiliser son mécanisme de mise à jour vers la version proposée. Si le gestionnaire refuse l’opération, le script vérifie que `yt-dlp` démarre encore avant de continuer. [Documentation de yt-dlp](https://github.com/yt-dlp/yt-dlp#update)

## Licence

Music Downloader est distribué sous [licence MIT](LICENSE). `yt-dlp`, FFmpeg et Deno s’installent séparément et gardent leurs propres licences.
