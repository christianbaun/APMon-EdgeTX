-- SPDX-License-Identifier: Apache-2.0
-- Setup check labels and order, loaded only with the optional check on SW.
-- Project version: 1.2.0
return {
  checks = { 'lq', 'RC-Link', 'armed', 'FC-Status', 'gps', 'GPS-Koordinaten',
    'fix', 'GPS-Fixtyp', 'voltage', 'Akkuspannung', 'current', 'Stromsensor',
    'used', 'mAh-Zähler', 'relative', 'Relative Höhe' },
  labels = {valid='Gültig', missing='Nicht gefunden', stale='Veraltet',
    invalid='Ungültig', noapi='API fehlt', unknown='Unbekannt',
    unreceived='Nicht empfangen', disabled='Nicht konfiguriert'},
  tips = {missing='Sensoren neu suchen', stale='Auf neue Werte warten',
    invalid='Quelle/Einheit prüfen', unknown='EdgeTX-Version prüfen',
    noapi='EdgeTX-Version prüfen', disabled='config.lua prüfen'},
  fixes = {[0]='Kein GPS', 'Kein Fix', '2D', '3D', 'DGPS', 'RTK float', 'RTK fix'},
}
