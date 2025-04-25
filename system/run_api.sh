# Příkaz pro testování API:

morbo api.pl

exit

<<COMMENT

Making it automatic (via systemd):

/etc/systemd/system/soudec-api.service for morbo (i.e., testing with only one client served at a time):

[Unit]
Description=SouDeC API Service

[Service]
ExecStart=/usr/bin/morbo /home/mirovsky/server/api.pl
WorkingDirectory=/home/mirovsky/server
Restart=always
User=mirovsky

[Install]
WantedBy=multi-user.target

===================
/etc/systemd/system/soudec-api.service for hypnotoad (i.e., production with multiple clients served at a time):

[Unit]
Description=SouDeC API Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/hypnotoad --foreground /home/mirovsky/server/api.pl
ExecStop=/usr/bin/hypnotoad --stop /home/mirovsky/server/api.pl
WorkingDirectory=/home/mirovsky/server
Restart=always
User=mirovsky

[Install]
WantedBy=multi-user.target

===================
Then:
   ```
   sudo systemctl daemon-reload
   sudo systemctl enable soudec-api
   sudo systemctl start soudec-api
   ```
Also:
   ```
   sudo systemctl status soudec-api
   sudo systemctl stop soudec-api
   sudo systemctl restart soudec-api
   ```

===========
Pozn.
Vstupní body služby REST API (např. info, process) je potřeba nastavit také v konfiguraci serveru Apache:
/etc/apache2/sites-available/000-default.conf; port 3000 pro morbo, 8080 pro hypnotoad, např.:

        # Proxy pro /api/process a /api/info
        ProxyPass "/api/process" "http://localhost:3000/api/process"
        ProxyPassReverse "/api/process" "http://localhost:3000/api/process"
        ProxyPass "/api/info" "http://localhost:3000/api/info"
        ProxyPassReverse "/api/info" "http://localhost:3000/api/info"

a pak provést
  sudo service apache2 restart

COMMENT
