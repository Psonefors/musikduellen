# Musikduellen – första spelbara prototypen

Flutter-app för **huvudtelefonen**. Andra telefoner ansluter via webbläsaren till huvudtelefonens lokala HTTP-server (port 8765). **Ingen extern spelserver/databas behövs.** Endast hämtning av Jamendo-låtar använder internet. Bygget är **inte körtestat på Android ännu**.

## Bygga APK med GitHub

1. Skapa ett **nytt repository** på GitHub, t.ex. `musikduellen` (helst privat för prototypen).
2. Ladda upp **innehållet i denna ZIP** till repositoryts rot (d.v.s. `pubspec.yaml`, `lib/`, `assets/` och den **dolda** mappen `.github/`). Ladda inte bara upp ZIP-filen som en fil.
3. Se till att standardgrenen är `main` eller `master`. Under **Actions** kör arbetsflödet **Bygg Musikduellen APK** automatiskt vid en push. Det kan också startas via **Run workflow**.
4. Öppna den färdiga körningen och ladda ner artefakten **Musikduellen-APK**. Packa upp den nedladdade artefakten och installera `app-release.apk` på Android-telefonen. Tillåt installation från den aktuella appen vid behov.
5. Om bygget misslyckas, öppna det röda steget i GitHub Actions och se felmeddelandet. Spara det för felsökning.

Detta är en **osignerad för butik men release-byggd** APK som Flutter signerar med utvecklingsnyckel enligt standard för ett nygenererat Android-projekt. Publicera inte som skarp app ännu.

## Användning

1. Slå på en Wi-Fi-hotspot på huvudtelefonen eller anslut alla telefoner till samma Wi-Fi. Andra telefoner ansluter till hotspoten **innan** de skannar QR-koden. Android-hotspots och vissa routrar kan blockera kommunikation mellan anslutna enheter; byt i så fall nätverk.
2. Öppna Musikduellen på huvudtelefonen och behåll appen i förgrunden. Välj **Duelläge** (standard) eller **Klassiskt**, genre, ljudläge och musikkälla.
3. Skanna QR-koden på övriga telefoner; deras webbläsare öppnar spelarvyn. Om IP-adressen i QR-koden är fel: använd 'Om QR-koden visar fel IP-adress' och ange huvudtelefonens LAN/hotspot-IP.
4. Minst två lag ansluter med olika namn. Spelledaren startar spelet.
5. Duelläge: lag satsar 1–3 poäng innan varje fråga. Rätt ger +satsning, fel ger -satsning, aldrig under 0. Klassiskt: +1 för rätt, ingen minuspoäng.
6. Frågan pågår i 30 sekunder, spelledaren kan avsluta tidigt. Efter rättning väljer spelledaren nästa runda. Först till 10 säkrar en placering. Spelet fortsätter tills bara sista laget återstår. Om flera går i mål samtidigt med lika poäng får de delad placering i prototypen.

## Musikkälla

- **Demo** fungerar utan internet, men innehåller bara tre **egenkomponerade testmelodier** med fiktiva låtnamn/artister och påhittade årtal. Här provar man teknik, inte riktig musikkunskap.
- **Jamendo** (valfritt) kan hämta riktiga musikspår och metadata. Skapa ett eget API-client-ID enligt instruktionerna på https://developer.jamendo.com/ och klistra in i appen. Genrerna motsvarar inte alltid Jamendos taggar och många spår kan sakna korrekta årtal. Appen använder datumet från Jamendo som frågans utgivningsår. **API-tillgång och rätt att spela/distribuera klipp är inte garanterade**: granska Jamendos API-villkor, respektive Creative Commons-licens, attribueringskrav och eventuella kommersiella begränsningar före användning utanför privata tester. Ingen Spotify-integration ingår.
- Ljudet hämtas till huvudtelefonen och kan skickas vidare över lokalt nätverk till spelarnas webbläsare.

## Tekniska begränsningar i v0.1

- Lokalt HTTP (ej HTTPS) används för LAN. Kör bara på betrott privat nätverk. Ingen inloggning eller kryptering; alltså **inte för publika Wi-Fi**.
- Synkronisering sker genom polling ungefär en gång per sekund, inte exakt tidslåst ljud. I hörlursläge kan webbläsare kräva att användaren trycker på **Spela klippet**, och ljudet kan börja osynkroniserat. Avancerad synk, köhantering och möjlighet att spela från externt musikabonnemang återstår.
- Endast exakta normaliserade fritextsvar godkänns (ignorerar versaler och skiljetecken); stavfel och alternativa namn godkänns ännu inte.
- Ingen beständig lagring efter att appen stängs, ingen admin-återanslutning, begränsat antal demospår, ingen testad minneshantering för långvariga spel.
- Spelarens webbsida använder lokalt HTTP och vissa Android/browser-konfigurationer kan blockera ljud eller nätverk; detta kräver enhetstester.
- När man når mål i samma runda och har samma poäng delas placeringen. Utslagsfrågor finns ännu inte.

## Projektinnehåll

- `lib/main.dart`: Flutter-spelledarvy och QR-kod.
- `lib/game.dart`: lokal HTTP-server, spelregler, musikimport, poäng, rättning.
- `assets/web/player.html`: responsiv mobilvy för spelare.
- `assets/audio`: testmelodier och originalsyntljud för nedräkning.
- `.github/workflows/android-apk.yml`: genererar Android-projektet och bygger APK i GitHub Actions.

> Före riktig release: kontrollera korrekt musiklicens, autentisering, felhantering, Android-hotspot-anslutning och ljudsynkronisering.
