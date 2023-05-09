# Works on a log file created by PuTTY terminal app by logging all serial input. It is a copy of data read from the P1 interface over time.
# Adjust the input path.


$inp = $args[0] 
if ($inp -eq $null) { $inp =  "P1 meter putty - 20230510.log" }


$TmPat = '0-0:1.0.0\((\d+)S\)' # regular expression pattern to match the number
$VoltPat = '1-0:[357]2.7.0\((\d+\.\d+)\*V\)' # regular expression pattern to match the number
$AmpPat = '1-0:[357]1.7.0\((\d+)\*A\)' # regular expression pattern to match the number

# $values = @()
$maxV =0
$maxA=0
$BlockTime = ""
$maxVtime=""
$maxAtime=""
$VPhase=""
$APhase=""

get-content $inp | foreach-object { 

    switch -regex ($_) {

    $TmPat { $BlockTime = $matches[1] }

    $VoltPat {
        $number = [double]$Matches[1] # convert the matched string to a double
    #    $values+= ($BlockTime, $number, "V")
        if ($number -gt $maxV) {
            $maxV = $number 
            $maxVtime = $BlockTime
            $VPhase=$_[4]
        }
    }

    $AmpPat {
        $number = [int]$Matches[1] # convert the matched string to an integer
    #    $values+= ($BlockTime, $number, "A")
        if ($number -gt $maxA) {
            $maxA = $number
            $maxAtime = $BlockTime
            $APhase=$_[4]
        }
    }
    }
}

# $maxv = $values | measure-object -maximum  | select-object -expandproperty maximum
if ( $inp -match "\d{8}" ) { $datefilename = $Matches[0] }

$dayst = $maxVtime.Substring(4,2)
$SummaryMax = "Maximum voltage: " + $maxv +  " V on phase" +$VPhase+ " on date " + $maxVtime.Substring(2,4) + " at " + $maxVtime.substring(6,4) + ".  Max current: " + $maxA + " A at " + $maxAtime.Substring(6,4) + " on phase"+ $APhase + " in log for date "+ $datefilename
write-output $summaryMax
