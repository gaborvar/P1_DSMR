$pattern = '1-0:[357]2.7.0\((\d+\.\d+)\*V\)' # regular expression pattern to match the number
$values = @()
$inp = "C:\Users\gabor\OneDrive\Dokumentumok\KocsagU\NapelemVillany\P1\P1 meter putty - 20230425.log"
get-content $inp | foreach-object { 
    if ($_ -match $pattern) {
        $number = [double]$Matches[1] # convert the matched string to a double
        $values+= $number
    }
}
write-output $matches
$maxv = $values | measure-object -maximum  | select-object -expandproperty maximum
if ( $inp -match "\d{8}" ) { $datefilename = $Matches[0] }

write-output $Matches 

write-host "Maximum: $maxv from ", $values.count , " in log for date: ", $datefilename

