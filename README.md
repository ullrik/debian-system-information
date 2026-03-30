# Récupération System Information
Script .sh pour récupérer des informations du système Debian qui produit une sortie json.
La logique voudrait que le script soit dans /usr/local/bin/ et un résultat dans /var/lib/info-system/xxx.json. Dans mon cas, j'ai fait plus simple avec /home/<user>/scripts/

## Exécution du programme
/!\ Il faut des privilèges pour exécuter le script :
```
bash system-info.sh
```
Exemple de fichier généré sur un Rasbperru PI Os Lite : 
```
{
  "timestamp": "2026-03-30T06:00:06+02:00",
  "model": "Raspberry Pi 4 Model B Rev 1.2",
  "system": {
    "pretty_name": "Debian GNU/Linux 13 (trixie)",
    "debian_version_full": "13.4",
    "version_id": "13",
    "version_codename": "trixie",
    "debian_latest": {
      "version": "13.4",
      "codename": "trixie",
      "is_latest_release": true
    },
    "apt": {
      "update_ok": true,
      "upgradable_count": 9,
      "up_to_date": false
    }
  },
  "rpi_eeprom": {
    "tool": "present",
    "current": "Fri  6 Feb 14:13:56 UTC 2026 (1770387236)",
    "latest": "Fri  9 Jan 16:12:13 UTC 2026 (1767975133)",
    "up_to_date": true
  }
}
```

## Tâche plannifiée
Mise en place d'une tâche plannifiée via "systemctl". 
Créer deux fichiers dans /etc/systemd/system :
* system-info.timer
* system-info.service
system-info.service :
```
[Unit]
Description=HostInformation
After=network-online.target

[Service]
Type=oneshot
WorkingDirectory=<path_vers_le_script>/scripts
ExecStart=/bin/bash <path_vers_le_script>/system-info.sh
User=root
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ReadWritePaths=<path_vers_le_script>/scripts

[Install]
WantedBy=multi-user.target
```

system-info.timer : 
```
[Unit]
Description=Lancement quotidien de system-info à 6h00

[Timer]
OnCalendar=*-*-* 06:00:00
Persistent=true

[Install]
WantedBy=timers.target
```

Recharger systemctl suite aux changements :
```
sudo systemctl daemon-reload
```

Activer la partie timer (/!\ ne pas activer la partie service)
```
sudo systemctl enable –now xxx.timer
```
En cas de changement dans timer, il faut faire « recharger systemctl suite à des changements » et :
```
sudo systemctl restart xxx.timer
```

Pour éteindre et désactivé même si reboot :
```
sudo systemctl stop xxx.service
sudo systemctl disable xxx.service
```

Pour tester si tout est ok  (si rien de répondu tout est ok)
```
systemd-analyze verify /etc/systemd/system/xxx.*
```

Pour voir les prochains cron systemctl : 
```
systemctl list-timers
```

## Récupération des éléments via Home Assistant (en Docker)
Si vous êtes en Docker, avec docker-compose, il faut rajouter le lien vers le répertoire ou se trouve la json, exemple :
```
    volumes:
      - <path_vers_le_script>/scripts:/host_scripts:ro
```

Ensuite dans Home Assistant, en deux étapes :
* via command_line (dans mon exemple je passe par un fichier externe à configuration.yaml via command_line.yaml) :
```
- sensor:
    name: "host_systeme_infos"
    command: "cat /host_scripts/system-info.json"
    scan_interval: 3600
    value_template: "{{ value_json.timestamp }}"
    json_attributes:
      - model
      - system
      - rpi_eeprom
      - timestamp
```
* via templates (dans mon exemple je passe par un fichier externe à configuration.yaml via templates.yaml) :
```
 - sensor:
    - name: "host systeme infos systeme"
      state: "{{ state_attr('sensor.host_systeme_infos', 'system').pretty_name }}"
      attributes:
        pretty_name: "{{ state_attr('sensor.host_systeme_infos', 'system').pretty_name }}"
        debian_version_full: "{{ state_attr('sensor.host_systeme_infos', 'system').debian_version_full }}"
        version_id: "{{ state_attr('sensor.host_systeme_infos', 'system').version_id }}"
        version_codename: "{{ state_attr('sensor.host_systeme_infos', 'system').version_codename }}"
        apt_update_ok: "{{ state_attr('sensor.host_systeme_infos', 'system').apt.update_ok }}"
        apt_upgradable_count: "{{ state_attr('sensor.host_systeme_infos', 'system').apt.upgradable_count }}"
        apt_up_to_date: "{{ state_attr('sensor.host_systeme_infos', 'system').apt.up_to_date }}"

    - name: host systeme infos system debian_latest
      state: "{{ state_attr('sensor.host_systeme_infos', 'system').debian_latest.is_latest_release }}"
      icon: mdi:debian
      attributes:
        version: "{{ state_attr('sensor.host_systeme_infos', 'system').debian_latest.version }}"
        codename: "{{ state_attr('sensor.host_systeme_infos', 'system').debian_latest.codename }}"
        is_latest_release: "{{ state_attr('sensor.host_systeme_infos', 'system').debian_latest.is_latest_release }}" 
 
    - name: host systeme infos system apt
      state: "{{ state_attr('sensor.host_systeme_infos', 'system').apt.up_to_date }}"
      icon: mdi:linux
      attributes:
        update_ok: "{{ state_attr('sensor.host_systeme_infos', 'system').apt.update_ok }}"
        upgradable_count: "{{ state_attr('sensor.host_systeme_infos', 'system').apt.upgradable_count }}"
        up_to_date: "{{ state_attr('sensor.host_systeme_infos', 'system').apt.up_to_date }}"
        
    - name: host systeme infos RPI EEPROM
      state: "{{ state_attr('sensor.host_systeme_infos', 'rpi_eeprom').up_to_date }}"
      icon: mdi:raspberry-pi
      attributes:
        tool: "{{ state_attr('sensor.host_systeme_infos', 'rpi_eeprom').tool }}"
        current: "{{ state_attr('sensor.host_systeme_infos', 'rpi_eeprom').current }}"
        latest: "{{ state_attr('sensor.host_systeme_infos', 'rpi_eeprom').latest }}"
        up_to_date: "{{ state_attr('sensor.host_systeme_infos', 'rpi_eeprom').up_to_date }}"
```

## Affichage dans Home Assistant
Voici un exemple d'affichage : 
![icons image](/docs/media/Apercu_HA_systeme-info.png)

le code : 
```
entities:
  - type: attribute
    entity: sensor.host_systeme_infos
    attribute: model
    name: Modèle
    icon: mdi:raspberry-pi
  - type: custom:fold-entity-row
    head:
      entity: sensor.host_systeme_infos_rpi_eeprom
      name: RPI EEPROM à jour
    entities:
      - type: attribute
        entity: sensor.host_systeme_infos_rpi_eeprom
        attribute: current
        name: Actuelle
      - type: attribute
        entity: sensor.host_systeme_infos_rpi_eeprom
        attribute: latest
        name: Derniére
  - type: divider
  - entity: sensor.host_systeme_infos_systeme
    icon: mdi:raspberry-pi
    name: Système
  - type: custom:template-entity-row
    entity: sensor.host_systeme_infos_systeme
    name: Système version
    icon: mdi:raspberry-pi
    state: >
      {{ state_attr('sensor.host_systeme_infos_systeme', 'debian_version_full')
      | string | replace(',', '.') }}
  - type: custom:fold-entity-row
    head:
      entity: sensor.host_systeme_infos_system_debian_latest
      name: Système Debian à jour
    entities:
      - type: custom:template-entity-row
        entity: sensor.host_systeme_infos_systeme
        name: Dernière version Debian
        icon: mdi:debian
        state: >
          {{ state_attr('sensor.host_systeme_infos_system_debian_latest',
          'version') | string | replace(',', '.') }}
      - type: attribute
        entity: sensor.host_systeme_infos_system_debian_latest
        attribute: codename
        name: Dernière version Debian
  - type: custom:fold-entity-row
    head:
      entity: sensor.host_systeme_infos_system_apt
      name: Système APT à jour
    entities:
      - type: attribute
        entity: sensor.host_systeme_infos_system_apt
        attribute: upgradable_count
        name: Nombre de mise à jour
```
