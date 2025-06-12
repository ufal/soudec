
echo "Searching for sources" >err

echo "Prezident republiky prohlásil, že na schůzku nepojede. Prezident příslušné obchodní společnosti řekl, že on ano." |\
./system/soudec.pl --stdin --ll 0 --output-format txt --store-statistics=tsv  2>>err

