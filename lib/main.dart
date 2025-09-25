import 'dart:developer';
import 'dart:io';
import 'package:ebom/const.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:path/path.dart' as path;
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      child: MaterialApp(
        title: 'Flutter Demo',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const Ebom(),
      ),
    );
  }
}

class Ebom extends StatefulWidget {
  const Ebom({super.key});

  @override
  State<Ebom> createState() => _EbomState();
}

class _EbomState extends State<Ebom> {
  late final WebViewController _controller;
  final _cookieManager = WebViewCookieManager();
  bool _isLoad = true;
  bool _hasError = false;
  bool _isProgress = false;
  List<String> fileUris = [];
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _initializeController();

    Future.delayed(Duration(milliseconds: 1500), () {
      _isLoad = false;
      setState(() {});
    });
  }

  Future<void> deleteFilesFromPaths(List<String> paths) async {
    for (var path in paths) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  // Fonction pour ouvrir le drawer
  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  @override
  void dispose() {
    deleteFilesFromPaths(fileUris);
    super.dispose();
  }

  Future<void> _reloadWebView() async {
    await _controller.loadRequest(Uri.parse(website));
    setState(() {
      _hasError = false;
      _isProgress = false;
    });
  }

  Future<void> openDialog(HttpAuthRequest httpRequest) async {
    final TextEditingController usernameTextController =
        TextEditingController();
    final TextEditingController passwordTextController =
        TextEditingController();

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('${httpRequest.host}: ${httpRequest.realm ?? '-'}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  decoration: const InputDecoration(labelText: 'Username'),
                  autofocus: true,
                  controller: usernameTextController,
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'Password'),
                  controller: passwordTextController,
                ),
              ],
            ),
          ),
          actions: <Widget>[
            // Explicitly cancel the request on iOS as the OS does not emit new
            // requests when a previous request is pending.
            TextButton(
              onPressed: () {
                httpRequest.onCancel();
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                httpRequest.onProceed(
                  WebViewCredential(
                    user: usernameTextController.text,
                    password: passwordTextController.text,
                  ),
                );
                Navigator.of(context).pop();
              },
              child: const Text('Authenticate'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    print(" 1 _hasError ${_hasError.toString()}");
    print(" 2 _isProgress ${_isProgress.toString()}");
    print(" 3 _isLoad ${_isLoad.toString()}");

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_hasError && !_isLoad && !_isProgress)
                Center(
                  child: GestureDetector(
                    onTap: () {}, // Tu peux mettre une action ici
                    child: Container(
                      decoration: const BoxDecoration(shape: BoxShape.circle),
                      child: Image.asset(
                        'assets/loader.gif',
                        fit: BoxFit.cover,
                        height: 110,
                        width: 110,
                      ),
                    ),
                  ),
                ),

              // WebView si pas de chargement et pas d’erreur
              if (!_isLoad && !_hasError && _isProgress)
                Expanded(child: WebViewWidget(controller: _controller)),

              // Page d’erreur personnalisée si erreur
              if (_hasError && !_isLoad)
                Expanded(child: _buildErrorPage(context)),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<String>> _androidFilePicker(FileSelectorParams params) async {
    // Determine les types acceptés
    final acceptsImages = params.acceptTypes.any((t) => t.startsWith("image/"));
    final acceptsVideos = params.acceptTypes.any((t) => t.startsWith("video/"));
    final acceptsAny =
        params.acceptTypes.isEmpty || params.acceptTypes.contains("*/*");

    // Si la page HTML demande spécifiquement la capture via caméra (ex: capture="camera")
    final wantsCamera = params.mode == FileSelectorMode.openMultiple;

    if (wantsCamera && acceptsImages) {
      // directement lancer la caméra pour une image
      final picked = await ImagePicker().pickImage(source: ImageSource.camera);
      if (picked != null) {
        return [Uri.file(picked.path).toString()];
      }
      return [];
    }
    if (wantsCamera && acceptsVideos) {
      final picked = await ImagePicker().pickVideo(source: ImageSource.camera);
      if (picked != null) {
        return [Uri.file(picked.path).toString()];
      }
      return [];
    }

    // Sinon, proposer un choix à l'utilisateur via un dialogue
    final resultChoice = await showModalBottomSheet<String>(
      context:
          context, // à définir : le contexte du widget contenant le WebView
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (acceptsImages)
                ListTile(
                  leading: Icon(Icons.photo_camera),
                  title: Text("Prendre une photo"),
                  onTap: () => Navigator.pop(ctx, "camera_image"),
                ),
              if (acceptsVideos)
                ListTile(
                  leading: Icon(Icons.videocam),
                  title: Text("Enregistrer une vidéo"),
                  onTap: () => Navigator.pop(ctx, "camera_video"),
                ),
              ListTile(
                leading: Icon(Icons.folder),
                title: Text("Choisir depuis fichiers"),
                onTap: () => Navigator.pop(ctx, "file"),
              ),
            ],
          ),
        );
      },
    );

    if (resultChoice == null) {
      return [];
    }

    switch (resultChoice) {
      case "camera_image":
        {
          final picked = await ImagePicker().pickImage(
            source: ImageSource.camera,
          );
          if (picked != null) {
            return [Uri.file(picked.path).toString()];
          }
          return [];
        }
      case "camera_video":
        {
          final picked = await ImagePicker().pickVideo(
            source: ImageSource.camera,
          );
          if (picked != null) {
            return [Uri.file(picked.path).toString()];
          }
          return [];
        }
      case "file":
      default:
        {
          // Enfin, ouverture du picker de fichiers
          final result = await FilePicker.platform.pickFiles(
            allowMultiple: params.mode == FileSelectorMode.openMultiple,
            type: FileType.any,
          );
          if (result == null) return [];
          return result.paths
              .whereType<String>()
              .map((path) => Uri.file(path).toString())
              .toList();
        }
    }
  }

  Future<void> _initializeController() async {
    // 1) Création du controller en utilisant le nouveau callback onPermissionRequest
    final params = const PlatformWebViewControllerCreationParams();
    final WebViewController
    controller = WebViewController.fromPlatformCreationParams(
      params,
      // ce callback est appelé quand le contenu web demande une permission (cam/mic, etc.)
      onPermissionRequest: (WebViewPermissionRequest request) {
        debugPrint('Permission web demandée: ${request.types}');

        // Politique simple : si la page demande caméra/micro on accorde (mais fais attention
        // en production : vérifier l'origine, demander à l'utilisateur, etc.)
        if (request.types.contains(WebViewPermissionResourceType.camera) ||
            request.types.contains(WebViewPermissionResourceType.microphone)) {
          // (Optionnel) demander les permissions runtime Android/iOS via permission_handler
          // NOTE: Request non-awaitable ici (callback sync), mais c'est souvent suffisant
          Permission.camera.request();
          Permission.microphone.request();

          // répondre à la requête web
          request.grant();
        } else {
          // par défaut on accorde ; adapte selon ton modèle de sécurité
          request.grant();
        }
      },
    );

    // 2) configuration classique
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (int progress) {
          debugPrint('WebView loading: $progress%');
        },
        onPageStarted: (String url) {
          debugPrint('Page started: $url');
        },
        onPageFinished: (String url) {
          debugPrint('Page finished: $url');
          setState(() {
            _isProgress = true;
          });
        },
        onWebResourceError: (error) {
          setState(() {
            _hasError = true;
          });
        },
        onHttpError: (HttpResponseError error) {
          debugPrint('HTTP error: ${error.response?.statusCode}');
        },
        onUrlChange: (UrlChange change) {
          debugPrint('URL changed: ${change.url}');
        },
        onHttpAuthRequest: (HttpAuthRequest request) {
          log("Darrel ${request}");
          openDialog(request);
        },
      ),
    );

    await controller.addJavaScriptChannel(
      'Toaster',
      onMessageReceived: (JavaScriptMessage message) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message.message)));
      },
    );

    await controller.loadRequest(Uri.parse(website));

    // 3) Platform-specific : Android
    if (controller.platform is AndroidWebViewController) {
      final androidController = controller.platform as AndroidWebViewController;

      try {
        await AndroidWebViewController.enableDebugging(true);
        await androidController.setMediaPlaybackRequiresUserGesture(false);

        // Remplacement de l'ancien setPermissionRequestHandler :
        // callback qui reçoit une PlatformWebViewPermissionRequest (Android implémentation disponible)
        await androidController.setOnPlatformPermissionRequest((
          PlatformWebViewPermissionRequest platformRequest,
        ) {
          debugPrint(
            'Platform permission request (Android): ${platformRequest.types}',
          );
          // Type concret : AndroidWebViewPermissionRequest, possède grant()/deny()
          // Ici on accorde — contrôle plus strict recommandé en prod.
          platformRequest.grant();
        });

        // Gérer <input type="file"> -> ouvrir un file picker natif et retourner les paths
        await androidController.setOnShowFileSelector(
          (FileSelectorParams params) async => await _androidFilePicker(params),
        );
      } catch (e, st) {
        log("Erreur configuration AndroidWebViewController: $e");
        log(st.toString());
      }
    }

    // 4) Platform-specific : iOS (WebKit)
    if (controller.platform is WebKitWebViewController) {
      final iosController = controller.platform as WebKitWebViewController;

      // Exemple : autoriser la lecture inline et le media capture est géré par onPermissionRequest
      // await iosController.setAllowsInlineMediaPlayback(true);
      // Remarque : la gestion fine des demandes média iOS est dispatchée vers onPermissionRequest
    }

    _controller = controller;
  }

  Widget _buildErrorPage(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: MediaQuery.of(context).size.height * 0.1),
          Image.asset(
            // 'assets/icons/eboom.jpg',
            'assets/ebom_market.png',
            // color: Colors.white,
            fit: BoxFit.fill,
            height: MediaQuery.of(context).size.height * 0.2,
            // width: 110,
          ),
          SizedBox(height: MediaQuery.of(context).size.height * 0.1),
          Align(
            // alignment: Al,d
            child: Text(
              "Oops! Pas de connexion internet",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 34,
                color: Colors.blue,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).size.height * 0.04),
          Align(
            // alignment: Al,d
            child: Text(
              "Une erreur s’est produite. Veuillez réessayer pour actualiser les données de l’application.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).size.height * 0.11),
          InkWell(
            onTap: () async {
              await _reloadWebView();
            },
            child: Container(
              width: MediaQuery.of(context).size.width - 100,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Center(
                child: Text(
                  "Réessayer",
                  style: TextStyle(fontSize: 24, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
