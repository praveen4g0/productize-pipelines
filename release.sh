#!/usr/bin/env python3

import yaml
from subprocess import Popen, PIPE, STDOUT, DEVNULL
import concurrent.futures
import sys
import koji as brew
import os 
import threading
import time
import argparse

def print_line():
    print("--------------------------------------------------------------------------------------------")

def build_image(config, test):
    print('Building an image for : {nvr}\n'.format(nvr = config['brew-package']))
    command = 'rhpkg --release pipelines-1.0-rhel-8 container-build'
    if "repo-url" in config:
        flag = ' --repo-url="{url}"'.format(url = config['repo-url'])
        command = command + flag
    if test:
        flag = ' --scratch'
        command = command + flag
    
    proc = Popen([command], stdout=PIPE, stderr=PIPE, shell=True)
    (status, err) = proc.communicate()
    if not status and err:
        print('Failed the build for : {nvr}'.format(nvr = config['brew-package']))
        print(err.decode())
        raise Exception("Failed image build")

    print('Completed the build for : {nvr}'.format(nvr = config['brew-package']))
    print(status.decode())
    print_line()

def get_latest_build(builds, nvr, version):
    latest = ""
    for build_id in iter(builds.splitlines()):
        build_name = nvr + "-v" + version
        if build_name.encode() not in build_id: 
            continue
        
        latest = build_id
    return latest.decode().partition(' ')[0]

def get_image_sha(build_id):
    if not build_id: 
        print('Build id is empty')
        return

    hub = brew.ClientSession('http://brewhub.devel.redhat.com/brewhub')
    print('Fething build for ' + build_id)
    build = hub.getBuild(build_id)
    return hub.listArchives(build['build_id'])[0]['extra']['docker']['digests']['application/vnd.docker.distribution.manifest.v2+json']

def exist(env, envVars):
    for i, e in enumerate(envVars):
        if e['name'] == env:
            return i
    return -1

def mirror_image(from_img, to_img):
    print('Mirroring image {from_img} ---> {to_img}'.format(from_img=from_img, to_img=to_img))
    print_line()
    command = 'oc image mirror --insecure {from_img} {to_img}'.format(from_img=from_img, to_img=to_img)
    proc = Popen([command], stdout=PIPE, stderr=PIPE, shell=True)
    (status, err) = proc.communicate()
    if not status and err:
        print('Failed to mirror images')
        print(err.decode())
        print_line()
        raise Exception('Failed mirroring')
    
    print('Mirroring completed for {img}'.format(img=to_img))
    print_line()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Tekton pipelines p12n release")
    parser.add_argument('-b', '--build-images', help='Want to build images, true if yes default is false', type=bool, default=False)
    parser.add_argument('-t', '--test-images', help='Want to perform scratch build, true if yes default is false', type=bool, default=False)
    parser.add_argument('-p', '--publish-operator', help='Want to perform scratch build, true if yes default is false', type=bool, default=False)
    args = parser.parse_args()
    script_dir = os.getcwd()

    #load config
    with open("image-config.yaml", 'r') as stream:
        try:
            release_config = yaml.safe_load(stream)
            print("Building the pipeline version : " + release_config['version'])
            print_line()
        except yaml.YAMLError as exc:
            print(exc)

    os.chdir("../dist-git")
    dir = os.getcwd()

    #start building images
    if args.build_images:
        build_threads = []
        failed_builds = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
            for name, components in release_config['components'].items():
                for component in components:
                    os.chdir('{pwd}/{dir}'.format(pwd = dir, dir = component["dir"]))
                    future = executor.submit(build_image, component, args.test_images)
                    build_threads.append(future)
                    time.sleep(5)

            for future in concurrent.futures.as_completed(build_threads):
                if future.exception():
                    failed_builds+= 1

        if failed_builds > 0:
            print('{builds} builds are failed '.format(builds=failed_builds))
            sys.exit(1)

    if args.test_images:
        print('Scratch builds are completed')
        sys.exit(0)

    #list images
    proc = Popen(['brew list-builds --quiet --prefix="openshift-pipelines" | sort -V'], stdout=PIPE, shell=True)
    (builds, err) = proc.communicate()
    if err:
        print('Unabled to list brew builds')
        sys.exit(1)

    #get image SHA for each component
    for name, components in release_config['components'].items():
        for component in components:
            build = get_latest_build(builds, component['brew-package'], release_config["version"])
            component['image_sha'] = get_image_sha(build)
            print(component)
            print_line()

    #update operator csv manifest
    operator_meata = release_config['operator-meta']
    os.chdir('{pwd}/{dir}'.format(pwd = dir, dir = operator_meata['dir']))
    with open('manifests/{ver}/openshift-pipelines-operator.v{ver}.clusterserviceversion.yaml'.format(ver = release_config['version']), 'r+') as csv_stream:
        try:
            csv = yaml.safe_load(csv_stream)
            deployment = csv['spec']['install']['spec']['deployments'][0]
            #replace operator image
            operator = release_config['components']['operator'][0]
            relatedImages = []
            for container in deployment['spec']['template']['spec']['containers']:
                if container['name'] != operator['replace']:
                    continue
                
                image = release_config['registry'] + operator['name'] + '@' + operator['image_sha']
                container['image'] = image
                
                for name, components in release_config['components'].items():
                    if name == 'operator':
                        continue

                    for component in components:
                        env = 'IMAGE_' + name + '_' + component['replace']
                        env = env.upper().replace('-', '_')
                        value = release_config['registry'] + component['name'] + '@' + component['image_sha']
                        envVar = {'name':env, 'value':value}
                        
                        index = exist(env, container['env'])
                        if index != -1:
                            container['env'][index]['value'] = value
                        else:
                            container['env'].append(envVar.copy())         
                        
                        relatedImages.append(envVar.copy())

            csv['spec']['relatedImages'] = relatedImages
            csv_stream.seek(0)
            csv_stream.truncate()
            yaml.safe_dump(csv, csv_stream, default_flow_style=False)

        except yaml.YAMLError as exc:
            print(exc)
    
    if args.publish_operator:
        print("Publishing the operator metadata(CSV)")
        print_line()
        
        os.chdir(script_dir)
        command = './meta.sh'.format(dir = script_dir)
        proc = Popen([command], stdout=PIPE, stderr=PIPE, shell=True)
        (status, err) = proc.communicate()
        if not status and err:
            print('Failed to execute meata build')
            print(err)
            sys.exit(1)
        print(status.decode())
        print_line()

        print("Mirroring images")
        print_line()
        os.chdir('{pwd}/{dir}'.format(pwd = dir, dir = operator_meata['dir']))
        mirror = release_config['mirror']
        mirror_threads = []
        failed_mirrors = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=mirror['parallel']) as executor:
            for name, components in release_config['components'].items():
                for component in components:
                    from_img = mirror['from-registry'] + '/' + mirror['from-org'] + component['name'] + '@' + component['image_sha']
                    to_img = mirror['to-registry'] + '/' + mirror['to-org'] + '/' + component['name'] + ':latest'
                    future = executor.submit(mirror_image, from_img, to_img)
                    mirror_threads.append(future)
                    
            for future in concurrent.futures.as_completed(mirror_threads):
                if future.exception():
                    failed_mirrors+= 1

        if failed_mirrors > 0:
            print('{mirrors} mirrorings are failed '.format(mirrors=failed_mirrors))
            sys.exit(1)





