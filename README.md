## deploymentreloader. archived, continuing the development as a kubectl plugin at https://github.com/marcelodevops/kubectl-reloader
### tool to update a kubernetes deployment everytime a mounted configMap or secret gets update
#### Features

- Discover all Deployments in the namespace dynamically.

- Watch all pods in each Deployment for ConfigMaps/Secrets.

- Trigger rolling updates automatically when any ConfigMap/Secret changes.

- Run as a single centralized pod—no need to manually list Deployments.


#### How to deploy

Build and push the Docker image:
```bash
docker build -t <your-registry>/auto-discover-reloader:latest .
docker push <your-registry>/auto-discover-reloader:latest
```

Replace <your-registry> in the Deployment manifest.

Apply RBAC and Deployment:
```bash
kubectl apply -f kubernetes/auto-discover-reloader-rbac.yaml
kubectl apply -f Kubernetes/auto-discover-reloader-deployment.yaml
```

The centralized reloader will automatically monitor all Deployments in the namespace.

Any change in ConfigMaps or Secrets triggers a rolling update for the affected Deployment.