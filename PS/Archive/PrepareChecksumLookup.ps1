# DSMR interface project
# This routine creates a table which will be used to determine the updated checksum value given a new byte in the stream. It creates a lookup table (vector). 

# input: each of the possible checksum values i.e. from 0 to xFFFF 
# assumption: the new byte in the stream that should update the checksum is zero. At run time we can recalculate the index into this vecor to accommodate all 255 other data points. 
# output: a vector (one dimensional array) of uint16 numbers, each is the updated checksum assuming the old checksum is the index and the incoming data point is zero.
# 65536 uint16 data points as checksum values are 16 bit 
# the lookup vector is written to a binary file "ChksumLookup.bin".

# note: We can cover all 65536 x 256 combinations of checksum and incoming data with just one vector. At run time the checksum needs to be XOR-ed with the incoming byte to calculate the correct index for the incoming byte.



    # Create an array with 65536 elements

$ChksumLookup = New-Object uint16[](65536)


    for ( $c=0; $c -lt $ChksumLookup.Length; $c++) {

            # checksum algorithm begins

        $chksum = $c   ##   Should be:   $c -bxor 0   but it equals $c

            for ($i = 0; $i -lt 8; $i++) {
                if ($chksum -band 1) {
                    $chksum = ($chksum -shr 1) -bxor 0xA001
                } else {
                    $chksum = $chksum -shr 1
                }
            }

    #        echo $c
       $ChksumLookup[$c] = $chksum
        
    }

# Open a file stream for binary write mode
$stream = New-Object System.IO.FileStream("ChksumLookup.bin", [System.IO.FileMode]::Create)
$writer = New-Object System.IO.BinaryWriter($stream)

# write each data point into the file.

for ($i = 0; $i -lt $ChksumLookup.Length; $i++) {
    $writer.Write($ChksumLookup[$i])
}

$writer.Close()
$stream.Close()



