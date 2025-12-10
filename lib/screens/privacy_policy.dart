import 'package:flutter/material.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title with modern styling
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade100, Colors.blue.shade50],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Privacy Policy',
                      style: TextStyle(
                        fontSize: 28, 
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Quiz Rewards App',
                      style: TextStyle(
                        fontSize: 18, 
                        fontWeight: FontWeight.w500,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Effective Date
              _buildInfoCard(
                icon: Icons.calendar_today,
                title: 'Effective Date',
                content: 'January 21, 2025\n\nLast Updated: January 21, 2025',
              ),

              // Introduction Section
              _buildSection(
                'Introduction',
                'Quiz Rewards App ("Company," "we," "us," or "our") operates the Quiz Rewards mobile application (the "App"). This Privacy Policy informs you of our policies regarding the collection, use, and disclosure of personal information when you use our App and the choices you have associated with that data.\n\nBy using our App, you agree to the collection and use of information in accordance with this Privacy Policy.',
              ),

              // Information Collection
              _buildSection(
                'Information We Collect',
                'We collect several types of information for various purposes to provide and improve our App:\n\n'
                '• Personal Information: Email address, username, profile information\n'
                '• Game Data: Quiz scores, leaderboard rankings, progress statistics\n'
                '• Device Information: Device type, operating system, unique device identifiers\n'
                '• Usage Data: App usage patterns, features accessed, time spent in app\n'
                '• Location Data: General location (country/region) for leaderboard purposes\n'
                '• Payment Information: For reward distribution (processed securely through third-party services)',
              ),

              // Reward System Section - NEW
              _buildHighlightSection(
                'Reward System & Monetary Prizes',
                '🏆 IMPORTANT: Our App features a competitive reward system:\n\n'
                '• We offer monetary prizes to top performers on our leaderboards\n'
                '• Rewards are distributed at our sole discretion based on performance metrics\n'
                '• Prize amounts, frequency, and eligibility criteria may change without notice\n'
                '• We reserve the right to start, modify, suspend, or discontinue reward campaigns at any time\n'
                '• Participation in contests is voluntary and subject to our Terms of Service\n'
                '• Winners may be required to provide additional verification information\n'
                '• Tax implications of prizes are the responsibility of recipients\n'
                '• We operate as a private company and may establish, modify, or cease operations at our discretion\n\n'
                'DISCLAIMER: Reward distribution is entirely discretionary and subject to verification of fair play. We reserve all rights regarding prize eligibility and distribution.',
              ),

              // Data Usage
              _buildSection(
                'How We Use Your Information',
                'We use collected information for:\n\n'
                '• Providing and maintaining App functionality\n'
                '• Processing and displaying leaderboard rankings\n'
                '• Distributing rewards and prizes to eligible users\n'
                '• Communicating about your account and App updates\n'
                '• Detecting and preventing fraud or cheating\n'
                '• Analyzing usage patterns to improve App performance\n'
                '• Complying with legal obligations\n'
                '• Providing customer support and technical assistance',
              ),

              // Data Sharing
              _buildSection(
                'Information Sharing and Disclosure',
                'We may share your information in the following circumstances:\n\n'
                '• Service Providers: Third-party services for payment processing, analytics, and app functionality\n'
                '• Legal Requirements: When required by law, court order, or government request\n'
                '• Business Transfers: In case of merger, acquisition, or sale of assets\n'
                '• Consent: When you explicitly consent to sharing\n'
                '• Safety: To protect rights, property, or safety of users and the public\n\n'
                'We do NOT sell your personal information to third parties for marketing purposes.',
              ),

              // Business Operations - NEW
              _buildHighlightSection(
                'Business Operations & Company Rights',
                '🏢 COMPANY OPERATIONS:\n\n'
                '• We operate as a private entity with full discretion over business operations\n'
                '• We may establish, modify, or discontinue services at any time\n'
                '• Reward programs are promotional activities subject to change\n'
                '• We reserve the right to modify app features, rules, or policies\n'
                '• Business decisions including prize distribution are made independently\n'
                '• We may cease operations or transfer the app to other entities\n'
                '• Users have no guaranteed rights to continued service or rewards',
              ),

              // Data Security
              _buildSection(
                'Data Security',
                'We implement appropriate security measures to protect your personal information:\n\n'
                '• Encryption of sensitive data in transit and at rest\n'
                '• Regular security assessments and updates\n'
                '• Limited access to personal information on a need-to-know basis\n'
                '• Secure payment processing through certified third-party providers\n\n'
                'However, no method of transmission over the internet is 100% secure. While we strive to protect your data, we cannot guarantee absolute security.',
              ),

              // User Rights
              _buildSection(
                'Your Rights and Choices',
                'You have the following rights regarding your personal information:\n\n'
                '• Access: Request access to your personal data\n'
                '• Correction: Request correction of inaccurate data\n'
                '• Deletion: Request deletion of your account and data\n'
                '• Portability: Request a copy of your data in a structured format\n'
                '• Withdrawal: Withdraw consent for data processing\n'
                '• Opt-out: Unsubscribe from promotional communications\n\n'
                'To exercise these rights, contact us using the information provided below.',
              ),

              // Data Retention
              _buildSection(
                'data Retention',
                'We retain your information for as long as necessary to:\n\n'
                '• Provide App services and maintain your account\n'
                '• Comply with legal obligations\n'
                '• Resolve disputes and enforce agreements\n'
                '• Maintain leaderboard history and fair play records\n\n'
                'Account data is typically retained for 3 years after account deletion, unless longer retention is required by law.',
              ),

              // International Transfers
              _buildSection(
                'International Data Transfers',
                'Your information may be transferred to and processed in countries other than your own. We ensure appropriate safeguards are in place for such transfers in accordance with applicable data protection laws.',
              ),

              // Changes to Policy
              _buildSection(
                'Changes to This Privacy Policy',
                'We may update this Privacy Policy periodically. We will notify you of significant changes by:\n\n'
                '• Posting an updated version in the App\n'
                '• Sending email notifications for material changes\n'
                '• Displaying in-app notifications\n\n'
                'Your continued use of the App after changes constitutes acceptance of the updated Privacy Policy.',
              ),

              // Legal Compliance
              _buildSection(
                'Legal Compliance',
                'This Privacy Policy is designed to comply with applicable data protection laws including GDPR, CCPA, and other regional privacy regulations. We are committed to protecting your privacy rights in accordance with applicable laws.',
              ),

              // Contact Information
              _buildContactSection(),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20, 
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHighlightSection(String title, String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade50, Colors.red.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.orange, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20, 
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({required IconData icon, required String title, required String content}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.blue, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18, 
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade100, Colors.blue.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.contact_support, color: Colors.green, size: 28),
              SizedBox(width: 12),
              Text(
                'Contact Us',
                style: TextStyle(
                  fontSize: 22, 
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'If you have any questions about this Privacy Policy or our data practices, please contact us:',
            style: TextStyle(
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          _buildContactItem(Icons.email, 'Email', 'contactgoal4service@gmail.com'),
          _buildContactItem(Icons.location_on, 'Address','[TN, india]'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.8),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '📧 For privacy-related inquiries, please allow 48-72 hours for response.',
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.blue, size: 20),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}