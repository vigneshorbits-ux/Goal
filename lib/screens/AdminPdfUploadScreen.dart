import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminPdfUploadScreen extends StatefulWidget {
  const AdminPdfUploadScreen({super.key});

  @override
  State<AdminPdfUploadScreen> createState() => _AdminPdfUploadScreenState();
}

class _AdminPdfUploadScreenState extends State<AdminPdfUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  String _pdfName = '';
  String _topic = '';
  String _creator = '';
  int _price = 0;
  File? _selectedFile;
  bool _isUploading = false;
  double _uploadProgress = 0;

  Future<void> _pickPdf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final fileSize = await file.length();
      const maxSize = 10 * 1024 * 1024; // 10MB limit

      if (fileSize > maxSize) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF must be less than 10MB'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      setState(() {
        _selectedFile = file;
        _uploadProgress = 0;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error selecting file: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _uploadPdfAndSaveProduct() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFile == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a PDF file'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    _formKey.currentState!.save();
    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      // Generate unique filename with timestamp
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'pdf_products/$timestamp/${_selectedFile!.path.split('/').last}';
      
      // Create reference to Firebase Storage location
      final storageRef = FirebaseStorage.instance.ref().child(filename);
      
      // Start upload task
      final uploadTask = storageRef.putFile(
        _selectedFile!,
        SettableMetadata(
          contentType: 'application/pdf',
          customMetadata: {
            'uploadedBy': 'admin',
            'originalName': _pdfName,
          },
        ),
      );

      // Listen to upload progress
      uploadTask.snapshotEvents.listen((taskSnapshot) {
        setState(() {
          _uploadProgress = taskSnapshot.bytesTransferred / taskSnapshot.totalBytes;
        });
      });

      // Wait for upload to complete
      final taskSnapshot = await uploadTask.whenComplete(() {});

      // Get download URL
      final pdfUrl = await taskSnapshot.ref.getDownloadURL();

      // Save product data to Firestore
      await FirebaseFirestore.instance.collection('pdf_products').add({
        'pdfName': _pdfName,
        'topic': _topic,
        'creator': _creator,
        'price': _price,
        'pdfUrl': pdfUrl,
        'fileSize': await _selectedFile!.length(),
        'uploadedAt': FieldValue.serverTimestamp(),
        'status': 'active',
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ PDF uploaded successfully!'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Reset form
      _formKey.currentState!.reset();
      setState(() {
        _selectedFile = null;
        _isUploading = false;
        _uploadProgress = 0;
        _price = 0;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Upload failed: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() {
        _isUploading = false;
        _uploadProgress = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filename = _selectedFile?.path.split('/').last ?? 'No file selected';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload PDF Product'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                decoration: InputDecoration(
                  labelText: 'PDF Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.description),
                ),
                validator: (val) => val == null || val.trim().isEmpty 
                    ? 'Please enter a name for the PDF' 
                    : null,
                onSaved: (val) => _pdfName = val!.trim(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: InputDecoration(
                  labelText: 'Topic/Category',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.category),
                ),
                validator: (val) => val == null || val.trim().isEmpty 
                    ? 'Please enter a topic/category' 
                    : null,
                onSaved: (val) => _topic = val!.trim(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: InputDecoration(
                  labelText: 'Creator/Author',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.person),
                ),
                validator: (val) => val == null || val.trim().isEmpty 
                    ? 'Please enter creator name' 
                    : null,
                onSaved: (val) => _creator = val!.trim(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: InputDecoration(
                  labelText: 'Price (₹)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.currency_rupee),
                ),
                keyboardType: TextInputType.number,
                validator: (val) {
                  if (val == null || val.isEmpty) return 'Please enter price';
                  final price = int.tryParse(val);
                  if (price == null || price <= 0) return 'Enter valid price (> ₹0)';
                  return null;
                },
                onSaved: (val) => _price = int.parse(val!),
              ),
              const SizedBox(height: 24),
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                    color: theme.dividerColor.withOpacity(0.2),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PDF File',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        filename,
                        style: TextStyle(
                          color: theme.textTheme.bodySmall?.color,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 16),
                      if (_isUploading) ...[
                        LinearProgressIndicator(
                          value: _uploadProgress,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(4),
                          valueColor: AlwaysStoppedAnimation(
                            theme.colorScheme.primary),
                          backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Uploading: ${(_uploadProgress * 100).toStringAsFixed(1)}%',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      if (!_isUploading)
                        OutlinedButton.icon(
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Select PDF File'),
                          onPressed: _pickPdf,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                icon: _isUploading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(_isUploading ? 'Uploading...' : 'Upload Product'),
                onPressed: _isUploading ? null : _uploadPdfAndSaveProduct,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}