# ``AppleAdsClient``

A Swift client for the Apple Search Ads API with automatic authentication and token management.

## Overview

AppleAdsClient handles OAuth token exchange, automatic refresh, and provides
access to the full Apple Search Ads Campaign Management API. The simplest way
to get started is with ``AppleAdsClient/AppleAdsClient/withClient(configuration:transport:body:)``,
which manages the entire client lifecycle for you.

@Snippet(path: "apple-ads-platform-api-swift/Snippets/quickstart")

## Topics

### Creating a Client

- ``AppleAdsClient/AppleAdsClient``

### Configuration

- ``AppleAdsClient/AppleAdsClient/Configuration``
- ``AppleAdsClient/AppleAdsClient/Configuration/AuthMode``

### Authentication

- ``TokenProvider``
- ``ClientSecretProvider``

### Request Context

- ``XApContext``

### Errors

- ``AppleAdsAuthError``
- ``AppleAdsAuthError/Code-swift.struct``

### Generated API

- ``Client``
