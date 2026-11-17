import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'game.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const MusicDuelApp()); }

class MusicDuelApp extends StatelessWidget {
  const MusicDuelApp({super.key});
  @override Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner:false, title:'Musikduellen',
    theme:ThemeData(brightness:Brightness.dark,useMaterial3:true,scaffoldBackgroundColor:const Color(0xff101222),
      colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xffd6ff61),brightness:Brightness.dark),
      cardTheme:const CardThemeData(color:Color(0xff1c2039))),
    home:const HostPage(),
  );
}

class HostPage extends StatefulWidget { const HostPage({super.key}); @override State<HostPage> createState()=>_HostPageState(); }
class _HostPageState extends State<HostPage> {
  final game=Game();
  final idController=TextEditingController();
  final ipController=TextEditingController();
  bool busy=false;
  static const genres=['Blandat','Rock','Pop','Electronic','Jazz','Metal','Folk','Hiphop','Classical'];
  @override void initState(){super.initState();game.addListener(_refresh);game.startServer();}
  void _refresh(){if(mounted)setState((){});}
  @override void dispose(){game.removeListener(_refresh);game.dispose();idController.dispose();ipController.dispose();super.dispose();}
  Widget section(String label,Widget child)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:Theme.of(context).textTheme.titleLarge),const SizedBox(height:12),child])));
  Widget line(String label,String text)=>Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(children:[Expanded(child:Text(label)),Text(text,style:const TextStyle(fontWeight:FontWeight.bold))]));
  Future<void> start() async {setState(()=>busy=true);await game.beginGame();if(mounted)setState(()=>busy=false);}
  Future<void> next() async {setState(()=>busy=true);await game.nextQuestion();if(mounted)setState(()=>busy=false);}

  @override Widget build(BuildContext context){
    final lobby=game.phase=='lobby', wagering=game.phase=='wager', question=game.phase=='question', reveal=game.phase=='reveal';
    final ready=game.teams.values.where((t)=>!t.qualified && t.betReady).length;
    final active=game.teams.values.where((t)=>!t.qualified).length;
    return Scaffold(appBar:AppBar(title:const Text('🎵 MUSIKDUELLEN'),backgroundColor:const Color(0xff101222)),
      body:ListView(padding:const EdgeInsets.fromLTRB(12,8,12,30),children:[
        if(game.error.isNotEmpty) Card(color:const Color(0xff593c30),child:Padding(padding:const EdgeInsets.all(14),child:Text(game.error))),
        if(lobby) ...[
          section('1. Välj spelregler',Column(children:[
            DropdownButtonFormField<String>(value:game.genre,decoration:const InputDecoration(labelText:'Musikgenre'),items:genres.map((g)=>DropdownMenuItem(value:g,child:Text(g))).toList(),onChanged:(v){if(v!=null)setState(()=>game.genre=v);}),
            const SizedBox(height:12),
            DropdownButtonFormField<String>(value:game.pointsMode,decoration:const InputDecoration(labelText:'Poängsystem'),items:const [DropdownMenuItem(value:'duel',child:Text('Duelläge – satsa 1–3 poäng')),DropdownMenuItem(value:'simple',child:Text('Klassiskt – +1 för rätt'))],onChanged:(v){if(v!=null)setState(()=>game.pointsMode=v);}),
            const SizedBox(height:12),
            DropdownButtonFormField<String>(value:game.playback,decoration:const InputDecoration(labelText:'Ljuduppspelning'),items:const [DropdownMenuItem(value:'party',child:Text('Partyläge – huvudtelefon')),DropdownMenuItem(value:'individual',child:Text('Hörlursläge – varje telefon'))],onChanged:(v){if(v!=null)setState(()=>game.playback=v);}),
            const SizedBox(height:12),
            DropdownButtonFormField<String>(value:game.source,decoration:const InputDecoration(labelText:'Musikkälla'),items:const [DropdownMenuItem(value:'demo',child:Text('Demo – 3 egna testmelodier')),DropdownMenuItem(value:'jamendo',child:Text('Jamendo – låtar via internet'))],onChanged:(v){if(v!=null)setState(()=>game.source=v);}),
            if(game.source=='jamendo') ...[const SizedBox(height:12),TextField(controller:idController,decoration:const InputDecoration(labelText:'Jamendo Client ID',hintText:'Från developer.jamendo.com'),onChanged:(v)=>game.jamendoId=v),const SizedBox(height:6),const Text('Jamendo-låtar har Creative Commons-licenser. Kontrollera att respektive licens och Jamendos API-villkor tillåter er användning.',style:TextStyle(fontSize:12))]
          ])),
          section('2. Dela QR-kod',Column(children:[
            const Text('Alla ansluter till samma Wi-Fi eller huvudtelefonens hotspot. Öppna QR-länken i webbläsaren.'),const SizedBox(height:12),
            if(game.address.isNotEmpty) ...[Center(child:Container(color:Colors.white,padding:const EdgeInsets.all(12),child:QrImageView(data:game.address,size:205))),const SizedBox(height:8),SelectableText(game.address,textAlign:TextAlign.center)] else const Text('Startar lokal server …'),
            const SizedBox(height:12),ExpansionTile(title:const Text('Om QR-koden visar fel IP-adress'),children:[TextField(controller:ipController,keyboardType:TextInputType.url,decoration:const InputDecoration(hintText:'192.168.43.1',labelText:'Lokal IP-adress')),TextButton(onPressed:(){game.setHostIp(ipController.text);},child:const Text('Använd adressen'))]),
          ])),
          section('3. Anslutna lag',Column(children:[
            for(final t in game.teams.values) line(t.name,'Redo'),
            if(game.teams.isEmpty) const Text('Inga lag anslutna ännu.'),
            const SizedBox(height:8),SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:busy||game.teams.length<2?null:start,icon:const Icon(Icons.play_arrow),label:Text(busy?'Laddar låtar …':'Starta spelet (${game.teams.length} lag)')))
          ])),
        ] else ...[
          section('Spelstatus',Column(children:[
            line('Runda','${game.round}'),line('Fas',{'wager':'Satsningar','question':'Fråga','reveal':'Resultat','finished':'Slutresultat'}[game.phase]??game.phase),
            if(wagering)line('Satsningar klara',game.pointsMode=='duel'?'$ready / $active':'Automatiskt'),
            if(question) ...[Text('${game.remaining}',style:const TextStyle(fontSize:72,fontWeight:FontWeight.bold)),Text(game.question,textAlign:TextAlign.center),const SizedBox(height:10),line('Inlämnade svar','${game.teams.values.where((t)=>!t.qualified&&t.answered).length} / $active')],
            if(reveal||game.phase=='finished') ...[
              Text(game.question,style:const TextStyle(fontWeight:FontWeight.bold)),
              line('Rätt svar',game.correct),
              Text(game.song?.credit??'',style:const TextStyle(fontSize:12)),
              const SizedBox(height:12),
              const Text('Lagresultat',style:TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
              for(final t in game.teams.values.where((t)=>t.lastRound==game.round))
                Card(child:Padding(padding:const EdgeInsets.all(10),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text('${t.lastCorrect==true?'✅':'❌'} ${t.name}',style:const TextStyle(fontWeight:FontWeight.bold)),
                  Text('Svar: ${t.lastAnswer}'),
                  Text('Poäng denna runda: ${t.lastChange>0?'+':''}${t.lastChange} • Totalt: ${t.points}')
                ])))
            ],
            const SizedBox(height:12),
            if(wagering)SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:busy?null:next,icon:const Icon(Icons.music_note),label:const Text('Spela nästa musikfråga'))),
            if(question)SizedBox(width:double.infinity,child:OutlinedButton(onPressed:game.reveal,child:const Text('Avsluta frågan och rätta'))),
            if(reveal)SizedBox(width:double.infinity,child:FilledButton(onPressed:game.nextWager,child:const Text('Fortsätt till nästa satsning'))),
            if(game.phase=='finished')const Text('🏆 Matchen är avslutad. Starta om appen för ett nytt spel.'),
          ])),
          section('Poängställning',Column(children:[for(final t in game.teams.values)line('${t.place!=null?'🏆 ${t.place}. ':''}${t.name}${t.qualified?' ✅':''}','${t.points} poäng')]))
        ],
        const SizedBox(height:10),const Text('Musikduellen v0.1 • Lokal spelserver • 10 poäng till mål',textAlign:TextAlign.center,style:TextStyle(color:Colors.grey,fontSize:12)),
      ]));
  }
}
