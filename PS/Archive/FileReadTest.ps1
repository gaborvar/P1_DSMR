


$stream = New-Object System.IO.FileStream("C:\Users\gabor\OneDrive\Dokumentumok\KocsagU\NapelemVillany\P1\P1 meter putty - 20230509.log", [System.IO.FileMode]::Open)
$TBreader = New-Object System.IO.BinaryReader($stream)

$telegramB = New-Object byte[](65536)


#for ($i = 0; $i -lt 65536; $i++) {
    $telegramB = $TBreader.ReadBytes(20000)
#}


$reader.Close()
$stream.Close()

$telegramS = [string]$telegramB


switch -regex ($telegramB) {

    "A"  {

        write-host ($telegramB[0..200])
        write-host $matches
        }

        }
