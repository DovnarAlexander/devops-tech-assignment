# Tasks

---

## Non-technical

### Architecture Design for "Innovate Inc."

One of our clients is a small startup called "Innovate Inc." They are developing a web application (details below) and are looking to deploy it on one of the two major cloud providers (AWS or GCP). They have limited experience with cloud infrastructure and are seeking your expertise to design a robust, scalable, secure, and cost-effective solution. They are particularly interested in leveraging managed Kubernetes and following best practices.

**Application Details:**

- **Type:** Web application with a REST API backend and a single-page application (SPA) frontend.
- **Technology Stack:** Backend: Python/Flask, Frontend: React, Database: PostgreSQL.
- **Traffic:** The expected initial load is low (a few hundred users per day), but they anticipate rapid growth to potentially millions of users.
- **Data:** Sensitive user data is handled, requiring strong security measures.
- **Deployment Frequency:** Aiming for continuous integration and continuous delivery (CI/CD).

**Assignment:**

Create an architectural design document for Innovate Inc.'s Cloud infrastructure. The document should address the following key areas:

1. **Cloud Environment Structure**
   - Recommend the optimal number and purpose of AWS accounts / GCP Projects for Innovate Inc. and justify your choice. Consider best practices for isolation, billing, and management.
2. **Network Design**
   - Design the Virtual Private Cloud (VPC) architecture.
   - Describe how you will secure the network.
3. **Compute Platform**
   - Detail how you will leverage Kubernetes Service to deploy and manage the application.
   - Describe your approach to node groups, scaling, and resource allocation within the cluster.
   - Explain your strategy for containerization, including image building, registry, and deployment processes.
4. **Database**
   - Recommend the appropriate service for the PostgreSQL database and justify your choice.
   - Outline your approach to database backups, high availability, and disaster recovery.

**Deliverables:** Please place your architecture assignment under the `architecture/` folder in the repository root. This folder should include a README architecture document with at least one HDL (High-Level Diagram) to illustrate the architecture.

---

## Technical

### Automate AWS EKS cluster setup with Karpenter, while utilizing Graviton and Spot instances

You've joined a new and growing startup.

The company wants to build its initial Kubernetes infrastructure on AWS. The team wants to leverage the latest autoscaling capabilities by Karpenter, as well as utilize Graviton and Spot instances for better price/performance.

They have asked you if you can help create the following:

- Terraform code that deploys an EKS cluster (whatever latest version is currently available) into a new dedicated VPC.
- The Terraform code should also deploy Karpenter with node pool(s) that can deploy both x86 and arm64 instances.
- Include a short readme that explains how to use the Terraform repo and that also demonstrates how an end-user (a developer from the company) can run a pod/deployment on x86 or Graviton instance inside the cluster.

**Deliverable:** Please place your technical assignment solution under the `terraform/` folder in the repository root. This folder should include all the necessary infrastructure as code needed in order to recreate a working POC of the above architecture.
