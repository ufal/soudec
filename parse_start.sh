
echo "Searching for sources" >err

#./parse.pl ../data/test/doc-1.xml.txt ../data/resources/spolehlivost_frazi.csv 2>err

for A in ../data/test/*.txt; do
  echo "=========================================================="
  echo "Searching for sources in $A"
  echo "=========================================================="
  ./parse.pl $A ../data/resources/spolehlivost_frazi.csv 2>>err
done
