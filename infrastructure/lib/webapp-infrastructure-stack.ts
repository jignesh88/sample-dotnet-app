import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as targets from 'aws-cdk-lib/aws-route53-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Construct } from 'constructs';

export class WebAppInfrastructureStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create a VPC
    const vpc = new ec2.Vpc(this, 'WebAppVPC', {
      maxAzs: 2,
      natGateways: 1,
    });

    // Create security group for the EC2 instance
    const webServerSG = new ec2.SecurityGroup(this, 'WebServerSG', {
      vpc,
      description: 'Security group for web server',
      allowAllOutbound: true,
    });

    // Allow HTTP and HTTPS traffic to the web server
    webServerSG.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic'
    );
    webServerSG.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS traffic'
    );
    
    // Allow RDP for management
    webServerSG.addIngressRule(
      ec2.Peer.ipv4('10.0.0.0/16'), // Restrict to your management CIDR
      ec2.Port.tcp(3389),
      'Allow RDP from management network'
    );

    // Create IAM role for the EC2 instance
    const webServerRole = new iam.Role(this, 'WebServerRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
      ],
    });

    // Create S3 bucket for deployment artifacts
    const deploymentBucket = new s3.Bucket(this, 'DeploymentBucket', {
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
    });

    // Grant the EC2 instance access to the deployment bucket
    deploymentBucket.grantReadWrite(webServerRole);

    // Create Windows EC2 instance with IIS
    const webServer = new ec2.Instance(this, 'WebServer', {
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      instanceType: ec2.InstanceType.of(
        ec2.InstanceClass.T3,
        ec2.InstanceSize.MEDIUM
      ),
      machineImage: ec2.MachineImage.latestWindows(
        ec2.WindowsVersion.WINDOWS_SERVER_2022_ENGLISH_FULL_BASE
      ),
      securityGroup: webServerSG,
      role: webServerRole,
      keyName: 'web-server-key', // Make sure this key exists in your AWS account
    });

    // Add user data script to install IIS and configure the web server
    webServer.addUserData(
      'powershell -Command "Install-WindowsFeature -Name Web-Server,Web-Asp-Net45,Web-Net-Ext45,Web-ISAPI-Ext,Web-ISAPI-Filter,Web-Mgmt-Console,Web-Scripting-Tools"',
      'powershell -Command "New-Item -Path C:\\WebApp -ItemType Directory -Force"',
      'powershell -Command "New-WebAppPool -Name WebAppPool"',
      'powershell -Command "New-Website -Name WebApp -PhysicalPath C:\\WebApp -ApplicationPool WebAppPool -Port 80"',
      'powershell -Command "Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force"',
      'powershell -Command "Install-Module -Name AWSPowerShell -Force"',
      'powershell -Command "Import-Module AWSPowerShell"',
      'powershell -Command "Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString(\'https://chocolatey.org/install.ps1\'))"',
      'powershell -Command "choco install awscli -y"',
      'powershell -Command "choco install cloudwatch-agent -y"'
    );

    // Create Application Load Balancer
    const alb = new elbv2.ApplicationLoadBalancer(this, 'WebAppALB', {
      vpc,
      internetFacing: true,
      securityGroup: new ec2.SecurityGroup(this, 'AlbSG', {
        vpc,
        allowAllOutbound: true,
      }),
    });

    // Allow traffic from ALB to EC2
    webServerSG.addIngressRule(
      ec2.Peer.securityGroupId(alb.connections.securityGroups[0].securityGroupId),
      ec2.Port.tcp(80),
      'Allow traffic from ALB'
    );

    // Add ALB listener
    const listener = alb.addListener('HttpListener', {
      port: 80,
      open: true,
    });

    // Add target group
    const targetGroup = listener.addTargets('WebAppTargets', {
      port: 80,
      targets: [new elbv2.InstanceTarget(webServer)],
      healthCheck: {
        path: '/',
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyHttpCodes: '200-299',
      },
    });

    // Create Route53 hosted zone (assuming it already exists)
    const hostedZone = route53.HostedZone.fromLookup(this, 'HostedZone', {
      domainName: 'example.com', // Replace with your domain
    });

    // Create Route53 record
    new route53.ARecord(this, 'WebAppDNS', {
      zone: hostedZone,
      recordName: 'webapp.example.com', // Replace with your subdomain
      target: route53.RecordTarget.fromAlias(
        new targets.LoadBalancerTarget(alb)
      ),
    });

    // Create CloudWatch dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'WebAppDashboard', {
      dashboardName: 'WebApp-Monitoring-Dashboard',
    });

    // Add CPU utilization metric
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'CPU Utilization',
        left: [webServer.metricCpuUtilization()],
      })
    );

    // Add memory utilization metric (requires CloudWatch agent)
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Memory Utilization',
        left: [
          new cloudwatch.Metric({
            namespace: 'CWAgent',
            metricName: 'Memory % Committed Bytes In Use',
            dimensionsMap: {
              InstanceId: webServer.instanceId,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(1),
          }),
        ],
      })
    );

    // Output the ALB DNS name and website URL
    new cdk.CfnOutput(this, 'LoadBalancerDNS', {
      value: alb.loadBalancerDnsName,
      description: 'The DNS name of the load balancer',
    });

    new cdk.CfnOutput(this, 'WebsiteURL', {
      value: 'http://webapp.example.com', // Replace with your domain
      description: 'The URL of the website',
    });

    new cdk.CfnOutput(this, 'DeploymentBucketName', {
      value: deploymentBucket.bucketName,
      description: 'The name of the S3 bucket for deployment artifacts',
    });
  }
}
