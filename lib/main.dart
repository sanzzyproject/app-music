import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart'; // Sesuai request dependencies

// 1. Dummy AudioHandler untuk memicu Foreground Service Android.
// Ini adalah "hack" agar OS Android mengira aplikasi ini sedang memutar
// audio native, sehingga WebView di dalamnya tidak di-kill saat di-minimize.
class WebAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  WebAudioHandler() {
    // Broadcast state 'playing' agar foreground service aktif
    playbackState.add(playbackState.value.copyWith(
      controls: [MediaControl.play, MediaControl.pause],
      processingState: AudioProcessingState.ready,
      playing: true,
    ));
  }
}

late AudioHandler _audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Inisialisasi AudioService sebelum runApp
  _audioHandler = await AudioService.init(
    builder: () => WebAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.musicapp.audio',
      androidNotificationChannelName: 'Web Music Playback',
      androidNotificationOngoing: true,
    ),
  );

  runApp(const MusicApp());
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Web Music Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.redAccent),
        useMaterial3: true, // Best practice Flutter 3.x
      ),
      home: const PlayerScreen(),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  InAppWebViewController? webViewController;
  bool isPlaying = true;
  double loadProgress = 0;

  @override
  Widget build(BuildContext context) {
    // 3. PopScope mencegah aplikasi tertutup saat tombol back ditekan
    return PopScope(
      canPop: false, // Cegah pop (tutup aplikasi)
      onPopInvoked: (didPop) async {
        if (didPop) return;
        // Jika web bisa kembali ke halaman sebelumnya, lakukan goBack
        if (await webViewController?.canGoBack() ?? false) {
          webViewController?.goBack();
        } 
        // Jika tidak bisa goBack, aplikasi tetap diam (tidak tertutup),
        // user harus menekan tombol Home untuk meminimize. Musik tetap jalan.
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              // 4. Implementasi InAppWebView
              InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri('https://apple-music-player-sable.vercel.app/search'),
                ),
                initialSettings: InAppWebViewSettings(
                  mediaPlaybackRequiresUserGesture: false, // Izinkan autoplay
                  allowsInlineMediaPlayback: true,
                  javaScriptEnabled: true,
                  backgroundPlaybackEnabled: true, // PENTING: Audio tetap jalan di background
                ),
                onWebViewCreated: (controller) {
                  webViewController = controller;
                },
                onProgressChanged: (controller, progress) {
                  setState(() {
                    loadProgress = progress / 100;
                  });
                },
              ),
              
              // 5. Progress Bar (Loading halaman web)
              if (loadProgress < 1.0)
                LinearProgressIndicator(
                  value: loadProgress,
                  color: Colors.redAccent,
                  backgroundColor: Colors.transparent,
                ),
            ],
          ),
        ),
        
        // 6. Tombol Play/Pause Overlay
        floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.redAccent,
          onPressed: () async {
            // Injeksi JavaScript untuk mencari tag audio/video di web dan men-toggle nya
            await webViewController?.evaluateJavascript(source: """
              var media = document.querySelector('video, audio');
              if (media) {
                if (media.paused) { media.play(); }
                else { media.pause(); }
              }
            """);
            setState(() {
              isPlaying = !isPlaying;
            });
          },
          child: Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
