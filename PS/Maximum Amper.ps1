$pattern = '1-0:[357]1.7.0\((\d+)\*A\)' # regular expression pattern to match the number
$values = @()
$inp = "C:\Users\gabor\OneDrive\Dokumentumok\KocsagU\NapelemVillany\P1\P1 meter putty - 20230426.log"
get-content $inp | foreach-object { if ($_ -match $pattern) {
    $number = [double]$Matches[1] # convert the matched string to a double
    $values+= $number
}
}

$maxv = $values | measure-object -maximum  | select-object -expandproperty maximum
write-host "Maximum: $maxv from ", $values.count
