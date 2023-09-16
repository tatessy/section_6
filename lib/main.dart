import 'dart:io';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:intl/intl.dart';
import 'package:test/firebase_options.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyAIApp());
}

class MyAIApp extends StatelessWidget {
  const MyAIApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "SMILE SNS",
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const MainForm(),
    );
  }
}

class MainForm extends StatefulWidget {
  const MainForm({super.key});

  @override
  _MainFormState createState() => _MainFormState();
}

class _MainFormState extends State<MainForm> {
  String _name = "";

  String _processingMessage = "";

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true,
      enableContours: true,
      enableClassification: true,
    ),
  );

  final ImagePicker _picker = ImagePicker();

  void _getImageAndFindFace(
      BuildContext context, ImageSource imageSource) async {
    setState(() {
      _processingMessage = "Processing...";
    });

    final pickedImage = await _picker.pickImage(source: imageSource);

    final File imageFile = File(pickedImage!.path);

    final visionImage = InputImage.fromFile(imageFile);

    List<Face> faces = await _faceDetector.processImage(visionImage);
    if (faces.isNotEmpty) {
      String imagePath =
          "/images/${const Uuid().v1()}${basename(pickedImage.path)}";
      final ref = FirebaseStorage.instance.ref().child(imagePath);

      final storedImage = await ref.putFile(imageFile);

      final String downloadUrl = await storedImage.ref.getDownloadURL();
      Face largestFace = findLargestFace(faces);

      FirebaseFirestore.instance.collection("smiles").add({
        "name": _name,
        "smile_prob": largestFace.smilingProbability,
        "image_url": downloadUrl,
        "date": Timestamp.now(),
      });
      Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const TimelinePage(),
          ));
    }

    setState(() {
      _processingMessage = "";
    });
  }

  Face findLargestFace(List<Face> faces) {
    Face largestFace = faces[0];
    for (Face face in faces) {
      if (face.boundingBox.height + face.boundingBox.width >
          largestFace.boundingBox.height + largestFace.boundingBox.width) {
        largestFace = face;
      }
    }
    return largestFace;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("SMILE SNS"),
        ),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            const Padding(padding: EdgeInsets.all(30.0)),
            Text(_processingMessage,
                style: const TextStyle(
                  color: Colors.lightBlue,
                  fontSize: 32.0,
                )),
            TextFormField(
              decoration: const InputDecoration(
                icon: Icon(Icons.person),
                hintText: "Please input your name.",
                labelText: "YOUR NAME",
              ),
              onChanged: (text) {
                setState(() {
                  _name = text;
                });
              },
            )
          ],
        ),
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            FloatingActionButton(
              onPressed: () {
                _getImageAndFindFace(context, ImageSource.gallery);
              },
              tooltip: "Select Image",
              heroTag: "gallery",
              child: const Icon(Icons.add_photo_alternate),
            ),
            const Padding(padding: EdgeInsets.all(10.0)),
            FloatingActionButton(
              onPressed: () {
                _getImageAndFindFace(context, ImageSource.camera);
              },
              tooltip: "Take Photo",
              heroTag: "camera",
              child: const Icon(Icons.add_a_photo),
            ),
          ],
        ));
  }
}

class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text("SMILE SNS"),
        ),
        body: Container(
          child: _buildBody(context),
        ));
  }

  Widget _buildBody(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection("smiles")
          .orderBy("date", descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LinearProgressIndicator();
        return _buildList(context, snapshot.data!.docs);
      },
    );
  }

  Widget _buildList(BuildContext context, List<DocumentSnapshot> snapList) {
    return ListView.builder(
        padding: const EdgeInsets.all(18.0),
        itemCount: snapList.length,
        itemBuilder: (context, i) {
          return _buildListItem(context, snapList[i]);
        });
  }

  Widget _buildListItem(BuildContext context, DocumentSnapshot snap) {
    Map<String, dynamic> data = snap.data() as Map<String, dynamic>;
    DateTime datetime = data["date"].toDate();
    var formatter = DateFormat("MM/dd HH:mm");
    String postDate = formatter.format(datetime);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 9.0),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: ListTile(
          leading: Text(postDate),
          title: Text(data["name"]),
          subtitle: Text(
              "${"は" + (data["smile_prob"] * 100.0).toStringAsFixed(1)}%の笑顔です。"),
          trailing: Text(
            _getIcon(data["smile_prob"]),
            style: const TextStyle(
              fontSize: 24,
            ),
          ),
          onTap: () {
            Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ImagePage(data["image_url"]),
                ));
          },
        ),
      ),
    );
  }

  String _getIcon(double smileProb) {
    String icon = "";
    if (smileProb < 0.2) {
      icon = "😧";
    } else if (smileProb < 0.4) {
      icon = "😌";
    } else if (smileProb < 0.6) {
      icon = "😀";
    } else if (smileProb < 0.8) {
      icon = "😄";
    } else {
      icon = "😆";
    }
    return icon;
  }
}

class ImagePage extends StatelessWidget {
  String _imageUrl = "";

  ImagePage(String imageUrl, {super.key}) {
    _imageUrl = imageUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("SMILE SNS"),
      ),
      body: Center(
        child: Image.network(_imageUrl),
      ),
    );
  }
}
