
echo "Searching for sources" >err

echo "Prezident republiky prohlásil, že na schůzku nepojede. Dále řekl, že ani ministr financí tam nebude." |\
./system/soudec.pl --stdin --ll 0 --output-format txt --output-statistics=html  2>>err

