# SampleWebApp - .NET Web Application

This repository contains a sample .NET web application with a complete CI/CD pipeline using TeamCity and AWS infrastructure.

## Project Structure

- `SampleWebApp/` - Main .NET web application
- `infrastructure/` - AWS CDK infrastructure code
- `teamcity/` - TeamCity configuration files
- `scripts/` - Deployment and utility scripts

## Technology Stack

- **Backend**: ASP.NET Core (.NET 8.0)
- **Build Tool**: TeamCity
- **Cloud Provider**: AWS
- **Infrastructure as Code**: AWS CDK
- **Web Server**: IIS on Windows Server
- **Load Balancer**: AWS Application Load Balancer
- **DNS**: AWS Route53
- **Performance Testing**: BlazeMeter
- **Monitoring**: CloudWatch

## Development Setup

### Prerequisites

- .NET SDK 8.0 or later
- AWS CLI
- AWS CDK
- Node.js (for CDK)

### Local Development

1. Clone the repository
2. Navigate to the SampleWebApp directory
3. Run the application:

```bash
cd SampleWebApp
dotnet run
```

4. Access the application at `https://localhost:5001`

## Infrastructure Setup

The infrastructure is managed using AWS CDK and includes:

- EC2 instance with Windows Server and IIS
- Application Load Balancer
- Route53 DNS configuration
- Security Groups
- IAM Roles and Policies

To deploy the infrastructure:

```bash
cd infrastructure
npm install
cdk deploy
```

## CI/CD Pipeline

The CI/CD pipeline is configured in TeamCity and includes the following steps:

1. Build the .NET application
2. Run unit tests
3. Deploy to AWS EC2 instance
4. Run BlazeMeter performance tests
5. Collect performance metrics
6. Publish results to GitHub

### TeamCity Configuration

TeamCity project configuration files are stored in the `teamcity` directory. The main build configuration includes:

- Build steps
- Deployment steps
- Performance testing steps
- Monitoring and reporting steps

## Security Best Practices

This project implements the following security best practices:

- HTTPS enforcement
- Secure AWS IAM policies (least privilege)
- Web application firewall (WAF) integration
- Regular security scanning
- Secrets management using AWS Secrets Manager
- Input validation and output encoding
- Protection against common web vulnerabilities (XSS, CSRF, etc.)

## Performance Testing

Performance testing is automated using BlazeMeter and integrated into the TeamCity pipeline. The tests include:

- Load testing
- Stress testing
- Endurance testing

Performance metrics are collected before and after testing and published to GitHub.

## Monitoring and Reporting

The application and infrastructure are monitored using AWS CloudWatch. Key metrics include:

- CPU utilization
- Memory usage
- Request count
- Response time
- Error rate

These metrics are collected and published as graphs to GitHub.

## Deployment

The application is deployed to an IIS-enabled EC2 instance through the TeamCity pipeline. The deployment process includes:

1. Building the application
2. Packaging the application
3. Transferring the package to the EC2 instance
4. Installing/updating the application on IIS
5. Verifying the deployment

## License

MIT
