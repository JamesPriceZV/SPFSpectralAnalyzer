@Article(
    title: "Microsoft 365 Enterprise Integration"
)

## Overview
Connect to Microsoft 365 to ground AI analysis in your organization's knowledge, export reports to SharePoint, collaborate through Microsoft Teams, and search enterprise content directly from the app. This integration uses MSAL authentication and the Microsoft Graph API.

## Setup
1. Open Settings and go to the Enterprise tab.
2. Enter your Microsoft 365 Client ID and Tenant ID (provided by your IT administrator).
3. Click Sign In. A browser window opens for Microsoft authentication.
4. After signing in, the app stores your authentication token securely.
5. Configure which features to enable: grounding, SharePoint export, Teams sync.

## Enterprise Grounding
Enterprise grounding enriches AI analysis with context from your organization's documents using the Microsoft 365 Copilot Retrieval API.

When enabled:
- The app automatically generates search queries from your spectral data, metrics, or formula ingredients.
- The Retrieval API searches your organization's SharePoint sites, OneDrive files, and Copilot Connectors.
- Relevant document excerpts are injected as context into the AI analysis prompt.
- Citations show which documents informed the analysis, with links back to the source.

Configure grounding in Settings:
- Enable or disable grounding per analysis function
- Filter which SharePoint sites and data sources to include
- View citation details in the Enterprise Citations panel

## SharePoint Export
Upload reports and data files directly to SharePoint or OneDrive:
1. Open the Reporting tab and generate a report (PDF, HTML, or other format).
2. Click Export to SharePoint or use the SharePoint Export panel.
3. Choose the destination site, library, and folder.
4. The upload begins with a progress indicator.
5. Large files (over 4 MB) use chunked upload sessions, supporting files up to approximately 2 GB.

Configure the default export destination in Settings to streamline repeated uploads.

## Teams Integration
Browse and interact with Microsoft Teams directly from the Enterprise tab:
- Browse teams, channels, and chats in the Teams panel.
- Send messages to Teams channels or chats, including spectral data and analysis results.
- Share chart snapshots and reports to Teams conversations.
- Pull chat history for reference during analysis.

Teams data syncs to a local cache with configurable polling intervals. Push notifications provide real-time updates when available.

## Enterprise Search
The Enterprise tab includes a dedicated search interface for querying Microsoft 365 content:
- Search across SharePoint, OneDrive, and connected data sources.
- Browse files in a SharePoint/OneDrive file tree.
- View search results with document previews and metadata.
- Open documents directly from search results.

## Privacy Notes
Enterprise features transmit data to Microsoft 365 services using your organization's credentials. All data flows through Microsoft Graph API endpoints governed by your tenant's security policies. API tokens are stored securely in the Keychain and refreshed automatically.
