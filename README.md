# SouDeC 

SouDeC (Source Detection and Classification) is command-line tool, a web application and a REST API service for detecting and classifying citation sources in Czech texts. Taking a plain text (typically, a newspaper article) as an input, it runs external services for dependency parsing and named entity recognition and then identifies citation phrases and sources in the text and classifies each source into one of five classes: anonymous, anonymous-partial, unofficial, official-non-political, official-political.

SouDeC Web Application is available at [http://quest.ms.mff.cuni.cz/soudec/](http://quest.ms.mff.cuni.cz/soudec/).

SouDeC REST API Web service is also available, with the API documentation at [https://ufal.mff.cuni.cz/soudec/api-reference](https://ufal.mff.cuni.cz/soudec/api-reference).

## License

Copyright 2022-2025 by Institute of Formal and Applied Linguistics, Faculty of Mathematics and Physics, Charles University, Czech Republic. 
The software is available under the [Mozilla Public License 2.0](https://www.mozilla.org/MPL/2.0/).

## Requirements

The software has been developed and tested on Linux (Ubuntu) and is run from the command line.
See [the documentation](https://ufal.mff.cuni.cz/soudec/users-manual).

## External services

SouDeC uses external services for its work:

- [UDPipe](https://github.com/ufal/udpipe/)
- [NameTag](https://github.com/ufal/nametag/)

