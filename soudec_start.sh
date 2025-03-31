
echo "Searching for sources" >err

echo "Předseda Poslanecké sněmovny řekl novinářům, že dnes schůze končí." |\
./system/soudec.pl --stdin --output-format txt  2>>err

