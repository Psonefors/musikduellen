import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

class Song {
  Song(this.title, this.artist, this.year, this.audioUrl, this.credit,
      {this.bytes, this.mime = 'audio/mpeg', this.album = ''});
  final String title, artist, audioUrl, credit, mime, album;
  final int year;
  Uint8List? bytes;
}

class Team {
  Team(this.id, this.name);
  final String id, name;
  int points = 0, bet = 1;
  String answer = '';
  bool? lastCorrect;
  int lastChange = 0;
  String lastAnswer = '';
  int lastRound = 0;
  bool betReady = false, answered = false, qualified = false;
  int? place;
}

class Game extends ChangeNotifier {
  Game();
  final Random random = Random.secure();
  final Map<String, Team> teams = {};
  final AudioPlayer _music = AudioPlayer();
  final AudioPlayer _tension = AudioPlayer();
  HttpServer? server;
  Timer? _clock;
  Timer? _suspenseTimer;
  String phase = 'lobby', genre = 'Blandat', pointsMode = 'duel', playback = 'party';
  String source = 'demo', jamendoId = '', error = '', hostIp = '';
  int round = 0, questionStartMs = 0;
  Song? song;
  String question = '', questionType = '', correct = '';
  List<String> choices = [];
  List<Song> catalog = [];
  final Set<String> used = {};
  String get address => hostIp.isEmpty ? '' : 'http://$hostIp:8765';
  int get remaining => phase == 'question' ? max(0, 30 - ((DateTime.now().millisecondsSinceEpoch - questionStartMs) ~/ 1000)) : 30;

  Future<void> startServer() async {
    if (server != null) return;
    try {
      server = await HttpServer.bind(InternetAddress.anyIPv4, 8765);
      server!.listen(_handleRequest);
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      final addresses = interfaces.expand((i) => i.addresses).where((a) => !a.isLoopback).toList();
      final preferred = addresses.where((a) => a.address.startsWith('192.168.') || a.address.startsWith('10.') || a.address.startsWith('172.')).toList();
      hostIp = (preferred.isNotEmpty ? preferred.first : (addresses.isNotEmpty ? addresses.first : InternetAddress.loopbackIPv4)).address;
      error = '';
    } catch (e) { error = 'Kunde inte starta lokal server: $e'; }
    notifyListeners();
  }

  void setHostIp(String ip) { hostIp = ip.trim(); notifyListeners(); }

  Future<void> beginGame() async {
    error = '';
    if (teams.length < 2) { error = 'Minst två lag måste ansluta.'; notifyListeners(); return; }
    try {
      if (source == 'jamendo') {
        if (jamendoId.trim().isEmpty) throw Exception('Ange ditt Jamendo Client ID i inställningarna.');
        catalog = await _loadJamendo();
      } else {
        catalog = [
          Song('Stjärnnatt', 'Demoorkestern', 2021, 'assets/audio/demo1.wav', 'Originalmelodi för Musikduellens demo', mime: 'audio/wav'),
          Song('Sommarvind', 'Testbandet', 2018, 'assets/audio/demo2.wav', 'Originalmelodi för Musikduellens demo', mime: 'audio/wav'),
          Song('Vinterljus', 'Studio Nord', 2023, 'assets/audio/demo3.wav', 'Originalmelodi för Musikduellens demo', mime: 'audio/wav'),
        ];
        for (final s in catalog) { s.bytes = (await rootBundle.load(s.audioUrl)).buffer.asUint8List(); }
      }
      if (catalog.length < 3) throw Exception('För få låtar hittades. Prova annan genre.');
      used.clear(); round = 0;
      for (final team in teams.values) { team.points=0; team.place=null; team.qualified=false; team.lastCorrect=null; team.lastChange=0; team.lastAnswer=''; team.lastRound=0; }
      phase = 'wager';
    } catch (e) { error = '$e'; }
    notifyListeners();
  }

  Future<List<Song>> _loadJamendo() async {
    final params = <String, String>{'client_id':jamendoId.trim(),'format':'json','limit':'100','order':'popularity_total','include':'licenses','audioformat':'mp31'};
    final tag = genre.toLowerCase();
    if (tag != 'blandat') params['tags'] = tag;
    final uri = Uri.https('api.jamendo.com','/v3.0/tracks/',params);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final req = await client.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) throw Exception('Jamendo svarade med HTTP ${res.statusCode}.');
      final data = jsonDecode(await utf8.decoder.bind(res).join()) as Map<String,dynamic>;
      final headers = data['headers'] as Map<String,dynamic>?;
      if (headers?['status'] != 'success') throw Exception('Jamendo: ${headers?['error_message'] ?? 'okänt API-fel'}');
      final entries = data['results'] as List<dynamic>? ?? [];
      final result = <Song>[];
      for (final item in entries) {
        final m = item as Map<String,dynamic>;
        final year = int.tryParse((m['releasedate'] ?? '').toString().split('-').first) ?? 0;
        final url = (m['audio'] ?? '').toString();
        if (url.isEmpty || year < 1950 || year > 2100 || (m['name'] ?? '').toString().isEmpty) continue;
        final license = (m['license_ccurl'] ?? '').toString();
        result.add(Song('${m['name']}', '${m['artist_name']}', year, url,
          'Musik: ${m['artist_name']} – ${m['name']} • Jamendo • $license', album: (m['album_name'] ?? '').toString().trim()));
      }
      result.shuffle(random);
      return result;
    } finally { client.close(force:true); }
  }

  Future<Uint8List> _download(Song track) async {
    if (track.bytes != null) return track.bytes!;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      final res = await (await client.getUrl(Uri.parse(track.audioUrl))).close();
      if (res.statusCode != 200) throw Exception('Ljudfil kunde inte hämtas (${res.statusCode}).');
      final builder = BytesBuilder(copy:false);
      await for (final chunk in res) {
        builder.add(chunk);
        if (builder.length > 18 * 1024 * 1024) throw Exception('Ljudfilen är för stor.');
      }
      track.bytes = builder.takeBytes();
      return track.bytes!;
    } finally { client.close(force:true); }
  }

  Future<void> nextQuestion() async {
    if (phase != 'wager' && phase != 'reveal') return;
    error = '';
    final eligible = teams.values.where((t)=>!t.qualified).toList();
    if (eligible.length <= 1) { phase = 'finished'; notifyListeners(); return; }
    if (pointsMode == 'duel' && eligible.any((t)=>!t.betReady)) {
      error = 'Alla aktiva lag måste låsa sin satsning.'; notifyListeners(); return;
    }
    if (catalog.every((s) => used.contains(s.audioUrl))) used.clear();
    final pool = catalog.where((s)=>!used.contains(s.audioUrl)).toList()..shuffle(random);
    song = pool.first;
    error = 'Hämtar musikklipp …'; notifyListeners();
    try { await _download(song!); } catch(e) {error='Ljudfel: $e'; notifyListeners(); return;}
    used.add(song!.audioUrl);
    final types = <String>['artist','year','title','choice'];
    if (song!.album.isNotEmpty) types.add('album');
    questionType = types[random.nextInt(types.length)];
    if (source == 'demo') {
      question = 'TESTFRÅGA – ${song!.title} av ${song!.artist}. Vilket år är testmelodin registrerad med?';
      questionType = 'year';
      correct = '${song!.year}';
      choices = [];
    } else if (questionType == 'year') { question='Vilket år släpptes den här låten?'; correct='${song!.year}'; choices=[]; }
    else if (questionType == 'title') {question='Vad heter den här låten?'; correct=song!.title; choices=[];}
    else if (questionType == 'artist') {question='Vilken artist framför den här låten?'; correct=song!.artist; choices=[];}
    else if (questionType == 'album') {question='Vad heter albumet där den här låten finns med?'; correct=song!.album; choices=[];}
    else {
      question='Vilken artist framför den här låten?'; correct=song!.artist;
      choices = [song!.artist, ...catalog.where((s)=>s.artist!=song!.artist).map((s)=>s.artist).toSet().take(3)];
      while (choices.length<4) { choices.add('Alternativ ${choices.length+1}'); }
      choices.shuffle(random);
    }
    round++; phase='question'; questionStartMs=DateTime.now().millisecondsSinceEpoch;
    for (final t in eligible) {t.answered=false;t.answer='';}
    error=''; notifyListeners();
    _clock?.cancel();
    _clock=Timer.periodic(const Duration(seconds:1), (_) { if (remaining==0) { reveal(); } else {notifyListeners();} });
    await _music.stop();await _tension.stop();
    if (playback=='party') {
      try { await _music.play(BytesSource(song!.bytes!)); } catch(e) {error='Kunde inte spela ljud: $e';notifyListeners();}
      _suspenseTimer?.cancel();
      _suspenseTimer=Timer(const Duration(seconds:15), () async {
        if (phase=='question') {
          try { await _music.stop(); await _tension.play(AssetSource('audio/suspense.wav')); } catch (_) {}
        }
      });
    }
  }

  bool _isCorrect(String answer) {
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-zåäö0-9]'), '');
    if (questionType == 'year') return int.tryParse(answer.trim()) == song!.year;
    return norm(answer) == norm(correct);
  }

  void reveal() {
    if (phase != 'question') return;
    _clock?.cancel(); _suspenseTimer?.cancel();
    _music.stop(); _tension.stop();
    for (final t in teams.values.where((t)=>!t.qualified)) {
      final points = pointsMode=='duel' ? t.bet : 1;
      final was = t.points;
      final isRight = t.answered && _isCorrect(t.answer);
      if (isRight) {t.points += points;}
      else if (pointsMode=='duel') {t.points=max(0,t.points-points);}
      t.lastCorrect = isRight;
      t.lastChange = t.points - was;
      t.lastAnswer = t.answered ? t.answer : 'Inget svar';
      t.lastRound = round;
      if (t.points >= 10) t.qualified=true;
      t.betReady = false;
    }
    final winners = teams.values.where((t)=>t.qualified && t.place==null).toList()
      ..sort((a,b)=>b.points.compareTo(a.points));
    int placed = teams.values.where((x)=>x.place!=null).length;
    int? previousScore;
    int currentRank = placed;
    for (final t in winners) {
      if (previousScore != t.points) currentRank = placed + 1;
      t.place = currentRank;
      previousScore = t.points;
      placed++;
    }
    final remainingTeams = teams.values.where((t)=>!t.qualified).toList();
    if (remainingTeams.length <= 1 && remainingTeams.isNotEmpty) {
      remainingTeams.first.place = teams.length;
    }
    phase = remainingTeams.length<=1 ? 'finished' : 'reveal';
    notifyListeners();
  }

  void nextWager() {
    if (phase!='reveal') return;
    for (final t in teams.values) {t.betReady=false;t.answered=false;t.answer='';t.bet=1;}
    phase='wager'; notifyListeners();
  }

  Map<String,dynamic> publicState(String? id) {
    final team = teams[id];
    return {
      'phase':phase,'round':round,'mode':pointsMode,'playback':playback,
      'serverNow':DateTime.now().millisecondsSinceEpoch,'start':questionStartMs,
      'question':(phase=='question'||phase=='reveal'||phase=='finished')?question:'',
      'type':questionType,'choices':choices,'correct':phase=='question'?'':correct,
      'credit':(phase=='reveal'||phase=='finished')?(song?.credit??''):'',
      'teams':teams.values.map((t)=>{'name':t.name,'points':t.points,'qualified':t.qualified,'place':t.place,'betReady':t.betReady,'answered':t.answered}).toList(),
      'you':team==null?null:{'id':team.id,'name':team.name,'betReady':team.betReady,'bet':team.bet,'answered':team.answered,'answer':team.answer,'qualified':team.qualified,
        'lastCorrect':(phase=='reveal'||phase=='finished')&&team.lastRound==round?team.lastCorrect:null,
        'lastAnswer':(phase=='reveal'||phase=='finished')&&team.lastRound==round?team.lastAnswer:'',
        'lastChange':(phase=='reveal'||phase=='finished')&&team.lastRound==round?team.lastChange:0},
    };
  }

  Future<void> _handleRequest(HttpRequest req) async {
    final res=req.response;
    res.headers.set('Cache-Control','no-store');
    try {
      final path=req.uri.path;
      if (req.method=='GET' && path=='/') {
        res.headers.contentType=ContentType.html;
        res.write(await rootBundle.loadString('assets/web/player.html'));
      } else if (req.method=='GET' && path=='/state') {
        _json(res,publicState(req.uri.queryParameters['id']));
      } else if (req.method=='GET' && path=='/audio') {
        if (phase!='question' || song?.bytes==null) {res.statusCode=404;res.write('Ingen aktuell låt');}
        else {res.headers.set('Content-Type',song!.mime);res.add(song!.bytes!);}
      } else if (req.method=='GET' && path=='/suspense') {
        res.headers.set('Content-Type','audio/wav');
        res.add((await rootBundle.load('assets/audio/suspense.wav')).buffer.asUint8List());
      } else if (req.method=='POST' && (path=='/join'||path=='/bet'||path=='/answer')) {
        final body=jsonDecode(await utf8.decoder.bind(req).join()) as Map<String,dynamic>;
        final id=(body['id']??'').toString();
        if (path=='/join') {
          if (phase!='lobby') { _bad(res,'Spelet har redan startat.'); }
          else {
            final name=(body['name']??'').toString().trim();
            if (name.isEmpty||name.length>28) {_bad(res,'Ange ett lagnamn med högst 28 tecken.');}
            else if (teams.values.any((t)=>t.name.toLowerCase()==name.toLowerCase())) {_bad(res,'Namnet används redan.');}
            else { final key='${DateTime.now().microsecondsSinceEpoch}${random.nextInt(999999)}';teams[key]=Team(key,name);_json(res,{'id':key});notifyListeners(); }
          }
        } else if (!teams.containsKey(id)) { _bad(res,'Okänt lag.'); }
        else if (teams[id]!.qualified) { _bad(res,'Laget är redan i mål.'); }
        else if (path=='/bet') {
          if (phase!='wager') { _bad(res,'Det går inte att satsa just nu.'); }
          else {final amount=int.tryParse('${body['bet']}')??0;
            if (amount<1||amount>3) {_bad(res,'Välj 1–3 poäng.');}
            else {teams[id]!..bet=amount..betReady=true;_json(res,{'ok':true});notifyListeners();}
          }
        } else {
          if (phase!='question') {_bad(res,'Svarstiden är slut.');}
          else if (teams[id]!.answered) {_bad(res,'Laget har redan svarat.');}
          else { final a=(body['answer']??'').toString().trim();
            if (a.isEmpty||a.length>100) {_bad(res,'Skriv ett svar.');}
            else {teams[id]!..answer=a..answered=true;_json(res,{'ok':true});notifyListeners();}
          }
        }
      } else {res.statusCode=404;res.write('Hittades inte');}
    } catch(e) {res.statusCode=500;_json(res,{'error':'Serverfel: $e'});}
    try {await res.close();} catch(_) {}
  }

  void _bad(HttpResponse res,String message) {res.statusCode=400;_json(res,{'error':message});}
  void _json(HttpResponse res,Map<String,dynamic> data) {
    res.headers.contentType=ContentType.json;res.write(jsonEncode(data));
  }

  @override void dispose() {
    _clock?.cancel();_suspenseTimer?.cancel();_music.dispose();_tension.dispose();server?.close(force:true);
    super.dispose();
  }
}
